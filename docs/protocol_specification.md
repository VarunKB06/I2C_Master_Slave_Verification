# Protocol and interface specification

| Item | Implemented |
|---|---|
| Addressing | 7-bit |
| Speed | Standard Mode 100 kHz (system clock 50 MHz, `quarter` = 125). Any `quarter` >= 4 works; the fast tests use 10 |
| Fast Mode 400 kHz | **not implemented** |
| Master / slave | one master, one slave (address configurable by `slave_addr`) |
| Data | 8 bits, MSB first, ACK/NACK |
| Repeated START, clock stretching | implemented (master waits; slave stretches by `stretch_cycles`) |
| Arbitration | not implemented |

## Master command interface
`cmd_valid` with `cmd_ready`; flags `cmd_start`, `cmd_write`, `cmd_read`, `cmd_stop`, `cmd_nack` (for reads: 1 = NACK),
`cmd_wdata`. Order inside one command: START (or repeated START if the master already owns the bus) -> write or read one
byte -> STOP. `done` pulses when finished; `slave_nack` (write), `rdata` (read), `timeout_err`, `illegal_cmd`, `bus_active`.
The 7-bit address and R/W bit are sent as a write byte right after START.

## Slave register access
Write transaction: address+W, first byte = register pointer, then data bytes written to `regs[pointer++]`.
Read transaction: address+R, bytes returned from `regs[pointer++]`. Pointer persists across transactions.
Register map: see README. `force_nack_data` (test input) makes the slave NACK data bytes; the address is still ACKed.

## Standard Mode timing checked (100 kHz test only)
tLOW >= 4.7 us, tHIGH >= 4.0 us, START hold >= 4.0 us, repeated-START setup >= 4.7 us, STOP setup >= 4.0 us,
bus-free time >= 4.7 us. The checker measures the bus wires; thresholds are parameters of `i2c_protocol_checker`.
