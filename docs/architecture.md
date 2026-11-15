# Architecture

## Open-drain bus
Devices expose `sda_oe` / `scl_oe` (1 = pull the line LOW, 0 = release). The bus model (`verification/i2c_bus_model.sv`)
combines them with `tri1` nets, so a line is high only if nobody pulls it low. No device ever drives a line high. A real
chip would map `*_oe` to a tri-state pad (`assign sda = oe ? 1'b0 : 1'bz`). Fault injectors `f_sda_low` / `f_scl_low`
hold a line low for stuck-bus tests.

## Timing: quarter ticks
One SCL period = 4 ticks of `i2c_clock_gen`; `quarter` = system clocks per tick (50 MHz clock, quarter 125 -> 100 kHz).
Per bit (master): tick0 set SDA (SCL low) -> tick1 release SCL -> tick2 sample SDA (SCL high) -> tick3 pull SCL low.
SCL high/low are each about 2 ticks (high is 2 clocks longer because the synchronizer delay is counted once per bit).
At 100 kHz that is about 5 us low and 5 us high against the Standard Mode minima of 4.7 us / 4.0 us.

```
 SCL  ‾‾‾‾‾\____/‾‾‾‾‾‾‾‾‾\____
 SDA  ____X data bit ________X__
        t0  t1   t2    t3
```
START (master): release SDA -> release SCL -> wait -> SDA low -> wait -> SCL low (SDA falls while SCL high).
STOP: SDA low (SCL low) -> release SCL -> wait -> release SDA (SDA rises while SCL high) -> bus-free wait.
Repeated START is the same sequence entered while the master already owns the bus (SDA is released first while SCL is low).

## Clock stretching
The master releases SCL and `hold = released && SCL still low` freezes the tick counter, so the FSM cannot advance until
the line really goes high. `i2c_timeout_monitor` counts the hold time and aborts the command (releasing both lines,
`timeout_err`) after `timeout_limit` clocks (0 = disabled). The slave stretches by holding SCL low for `stretch_cycles`
clocks after the 8th bit of a received byte and before presenting each read byte.

## Master FSM (`i2c_master.sv`)
Original plan states map onto a byte-level FSM; address/data write and read share the bit engine.
| State | Original plan states | Behaviour |
|---|---|---|
| IDLE | IDLE | `cmd_ready`; latches a command; illegal commands (data without START, STOP without START, write+read) finish with `illegal_cmd` |
| START | START, REPEATED_START | 6-step START sequence (5 ticks of waiting/driving), then SCL low |
| BIT | ADDRESS, ADDRESS_ACK, WRITE_DATA, WRITE_ACK, READ_DATA, READ_ACK | bit cell with `bcnt` 0..7 data, 8 = ACK; write samples ACK (`slave_nack`), read answers ACK/NACK (`cmd_nack`) |
| STOP | STOP | 4-step STOP sequence, then bus-free wait |
| DONE | COMPLETE / ERROR | one-cycle `done`; timeout aborts here with `timeout_err` |

## Slave FSM (`i2c_slave.sv`)
IDLE -> (START) ADDR (8 rising edges) -> on the falling edge: address match -> ADDR_ACK (SDA low for the 9th clock) or WAIT.
After ADDR_ACK: write -> WRITE / WR_ACK loop (first byte = pointer), read -> READ / RD_ACK loop (master ACK continues,
NACK -> WAIT). WAIT ignores traffic until STOP (-> IDLE) or START (-> ADDR). START/STOP are honoured in every state.
Slave state mapping: ADDRESS_RECEIVE=ADDR, ADDRESS_COMPARE (combinational decoder), ADDRESS_ACK=ADDR_ACK,
DATA_RECEIVE=WRITE, DATA_ACK=WR_ACK, DATA_TRANSMIT=READ, MASTER_ACK_RECEIVE=RD_ACK, WAIT_FOR_STOP_OR_RESTART=WAIT.

## Reset
Asynchronous active-low `rst_n` on both devices: lines released, FSMs idle, slave registers cleared. System reset is
the supported recovery for an aborted transaction that leaves the slave driving SDA.
