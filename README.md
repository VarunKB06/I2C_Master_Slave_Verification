# I2C Master-Slave Controller with Self-Checking Verification

Synthesizable-style SystemVerilog I2C **master** and **slave** (7-bit addressing, ACK/NACK, repeated START, clock
stretching, timeout) with a slave register bank, an **open-drain bus model with pull-ups**, an independent bus monitor,
a reference-model scoreboard, a procedural protocol/timing checker, functional coverage, directed + randomized tests
and a GitHub Actions regression (Icarus Verilog).

> **Status: simulated and passing.** The full regression (32 tests) passes in **GitHub Actions with Icarus Verilog**
> for seeds 1, 2 and 3 (results below, logs in `reports/ci_logs/`). The protocol checks are procedural, not native SVA.
> Implemented: Standard Mode (100 kHz) timing, single master. **Not implemented:** Fast Mode, multi-master
> arbitration, 10-bit addressing, bus-clear recovery, SDA-stuck-low detection.

## I2C in one minute
- Two wires, **SDA** (data) and **SCL** (clock), both open drain with pull-up resistors: a device either pulls the
  line low or releases it; nobody drives it high. The testbench models this with `tri1` nets.
- **START:** SDA falls while SCL is high. **STOP:** SDA rises while SCL is high. Otherwise SDA only changes while SCL is low.
- Each byte is 8 bits MSB first plus a 9th clock for **ACK** (receiver pulls SDA low) or **NACK** (SDA stays high).
- First byte after START = 7-bit address + R/W bit. A **repeated START** (START without STOP) changes direction without
  releasing the bus. A slave may hold SCL low (**clock stretching**) and the master must wait.

## Architecture
```
 test driver --> byte-command interface --> i2c_master ---.                       .--- i2c_slave --- i2c_register_bank
 (cmd_valid, start/stop/write/read/nack)     (FSM, clock gen, timeout)    SDA/SCL  (start/stop det., FSM, address decoder)
                                                             '--- i2c_bus_model (open drain + pull-ups) ---'
                                                                         |
                          i2c_monitor (decodes SDA/SCL only) --> scoreboard (reference model) / protocol checker / coverage
```
| Module | Role |
|---|---|
| `i2c_master.sv` | Byte-command master: START / repeated START / write byte + ACK / read byte + ACK or NACK / STOP, stretch wait, timeout |
| `i2c_clock_gen.sv` | Quarter-period tick generator; frozen while SCL is held low after being released (stretching) |
| `i2c_timeout_monitor.sv` | Counts clocks of stretch / stuck-low; aborts the master after the limit |
| `i2c_slave.sv` | Address match, ACK/NACK, pointer-based register access, optional clock stretching |
| `i2c_start_stop_detector.sv` | START, STOP, SCL rise/fall pulses from synchronized samples |
| `i2c_address_decoder.sv` | 7-bit address compare + R/W |
| `i2c_register_bank.sv` | DATA, STATUS, CONTROL, ID registers |

Details: [docs/architecture.md](docs/architecture.md) (FSMs, timing), [docs/protocol_specification.md](docs/protocol_specification.md)
(register map, interface), [docs/implementation_notes.md](docs/implementation_notes.md) (deviations from the original plan).

### Register map (slave)
| Address | Register | Access | Notes |
|---|---|---|---|
| 0x00 | DATA | R/W | write sets STATUS.data_valid; read clears it |
| 0x01 | STATUS | R | [0] data_valid, [1] invalid_access (sticky, cleared by reading STATUS) |
| 0x02 | CONTROL | R/W | reset 0x00 |
| 0x03 | ID | R | 0xA5 |

First data byte of a write transaction loads the register pointer; the pointer auto-increments after every access and
persists across transactions. Writes to read-only/unknown registers are ignored and set `invalid_access`.

## Verification
- **Bus monitor** (`i2c_monitor.sv`): decodes START / repeated START / STOP / bytes from the wires, never from DUT state.
- **Scoreboard** (`scoreboard.sv`): the driver registers the expected bus events before each command; the scoreboard
  compares them with the monitor events, checks address decoding, ACK/NACK, write data and master ACK/NACK, and predicts
  every read byte with an independent model of the register bank.
- **Protocol checker** (`assertions.sv`): *procedural* checks (not SVA) for tLOW, tHIGH, START hold/setup, STOP setup,
  bus-free time (enabled in the 100 kHz test) and stretch measurement; the monitor flags START/STOP in the middle of a byte.
- **Coverage** (`coverage.sv`): hand-written event and cross bins (not code coverage).
- **Tests** (32): Stage 1 basic, Stage 2 protocol + advanced transactions, Stage 3 timing / stretching / errors / random.
  Matrix with status: [docs/verification_plan.md](docs/verification_plan.md).

## Run
```
bash scripts/run_stage1.sh            # basic tests
bash scripts/run_stage2.sh            # protocol and advanced transactions
bash scripts/run_stage3.sh            # timing, errors, random
bash scripts/run_all.sh               # stages 1-3 + combined run; nonzero exit on ANY failure
SEED=7 WAVES=1 bash scripts/run_all.sh iverilog   # WAVES=1 writes waveforms/tb_i2c_system.vcd (GTKWave)
```
Needs Icarus Verilog with `-g2012` (version 12 recommended). Logs go to `reports/`.

## Continuous integration
`.github/workflows/regression.yml` compiles and runs `tb_i2c_system` for seeds 1, 2, 3 (all stages), fails on any
compile error, non-zero simulator status, failed test, scoreboard error or checker failure, uploads logs
(`sim-logs-seed-N`), and a second job uploads a stage-1 VCD (`waveform-stage1-seed1`). Trigger it with a push or
*Actions -> I2C regression -> Run workflow*.

## Results
### GitHub Actions (Icarus Verilog, `+STAGE=0`, all 32 tests)
| Item | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Tests passed / failed | 32 / 0 | 32 / 0 | 32 / 0 |
| Scoreboard errors | 0 | 0 | 0 |
| Protocol checker failures | 0 | 0 | 0 |
| Monitor protocol errors (START/STOP mid-byte) | 0 | 0 | 0 |
| Total checks | 4,987 | 4,970 | 5,007 |
| Transactions completed / bytes compared | 406 / 1,524 | 406 / 1,496 | 406 / 1,508 |
| Checker evaluations | 29,420 | 28,892 | 29,102 |
| Functional EVENT bins | 25 / 25 | 25 / 25 | 25 / 25 |
| Functional CROSS bins | 14 / 14 | 14 / 14 | 14 / 14 |
| Final | PASS | PASS | PASS |

Source: `reports/ci_logs/sim_seed{1,2,3}.log`; seed-1 extracts in `reports/simulation_summary.txt`,
`reports/protocol_checker_summary.txt` and `reports/functional_coverage.txt`. The stage-1 waveform job (8 tests) also passed.
Icarus prints a harmless "no explicit time unit" warning for the RTL files (they contain no delays).

Notes
- **100 kHz timing (T31):** with the 100 kHz configuration the checker verified tLOW, tHIGH, START hold/setup, STOP setup and
  bus-free time against the Standard Mode minima, and the measured SCL period was within 9.9-10.2 us. All other tests use a
  faster simulation configuration (`quarter` = 10, about 0.84 us per bit) to keep runs short.
- **Clock stretching, timeout, resets:** T35-T38 and T40-T47 passed. In T38 the log shows the documented limitation: after the
  master aborts on a timeout the slave keeps SDA low until a system reset.
- **History:** the first CI run had 29 failing tests caused by a false positive in the bus monitor (it counted the clock edge
  before a STOP/repeated START as a data bit); scoreboard and checker errors were 0. The monitor was fixed and T24 was added to
  close the last cross bin (13/14 -> 14/14).
- Coverage is hand-written functional coverage (event and cross bins), not RTL code coverage. The error-type x recovery cross
  is not implemented.

## Waveforms (GTKWave)
The waveform is the CI VCD [`waveforms/tb_i2c_system_stage1_seed1.vcd`](waveforms/tb_i2c_system_stage1_seed1.vcd) (stage 1,
tests T1-T10, 0 to 310 us). Screenshots below show the same signals in each view: `scl`, `sda`, `m_sda_oe`, `m_scl_oe`,
`s_sda_oe`, `s_scl_oe` (1 = that device pulls the line low) and the monitor's `evt_kind` / `evt_val` / `evt_nack`.

![Write transaction](waveforms/gtkwave_i2c_write_txn.png)
*T8 write, 120-145 us: START, address byte 0xA0 (0x50 + write) ACKed by the slave, register pointer 0x00, data 0x5A, STOP. The
slave pulls SDA low during every 9th clock (ACK); SDA changes only while SCL is low except for START and STOP.*

![Repeated START read](waveforms/gtkwave_i2c_repeated_start_read.png)
*T8 read-back, 145-179 us: START, address 0xA0, pointer 0x00, repeated START (no STOP in between), address 0xA1 (read), data 0x5A
returned by the slave, master NACK on the last byte (master releases SDA in the 9th clock), STOP.*

![Address NACK](waveforms/gtkwave_i2c_address_nack.png)
*T7, 100-109 us: address 0xA2 does not match the slave (0xA0/0xA1 are its write/read addresses), so SDA stays high in the 9th clock
(NACK) and the master ends the transaction with STOP.*

## Known limitations
- Standard Mode only (100 kHz); the 400 kHz mode is not implemented or tested.
- Single master; no arbitration. 7-bit addresses only; no general call, no 10-bit addressing.
- Master is driven through a byte-command interface (the address is sent as a write byte after START).
- No bus-clear: a slave left driving SDA after a master abort is recovered by a system reset (test T38).
- SDA stuck low is not detected (only SCL stuck low / over-long stretch triggers the timeout).
- The slave needs a system clock of roughly 8x SCL or more (`quarter` >= 6 recommended; minimum 4).
- Protocol checks are procedural, not native SVA; cross coverage for error type x recovery is pending.
