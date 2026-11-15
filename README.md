# I2C Master-Slave Controller with Self-Checking Verification

Synthesizable-style SystemVerilog I2C **master** and **slave** (7-bit addressing, ACK/NACK, repeated START, clock
stretching, timeout) with a slave register bank, an **open-drain bus model with pull-ups**, an independent bus monitor,
a reference-model scoreboard, a procedural protocol/timing checker, functional coverage, directed + randomized tests
and a GitHub Actions regression (Icarus Verilog).

> **Status: first draft, not yet run.** This code was written without access to a simulator. No compile result,
> test result, coverage number or waveform exists yet. Run `bash scripts/run_all.sh` locally or the GitHub Actions
> workflow, then replace this note and the empty results section with real output from `reports/`.
> Implemented: Standard Mode (100 kHz) timing, single master. **Not implemented:** Fast Mode, multi-master
> arbitration, 10-bit addressing, bus-clear recovery, native SVA.

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
- **Tests** (31): Stage 1 basic, Stage 2 protocol + advanced transactions, Stage 3 timing / stretching / errors / random.
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
Not available yet: the project has not been compiled or simulated. After the first CI run, copy the summary
(`reports/simulation_summary.txt`), coverage report and per-seed logs here.

## Known limitations
- Standard Mode only (100 kHz); the 400 kHz mode is not implemented or tested.
- Single master; no arbitration. 7-bit addresses only; no general call, no 10-bit addressing.
- Master is driven through a byte-command interface (the address is sent as a write byte after START).
- No bus-clear: a slave left driving SDA after a master abort is recovered by a system reset (test T38).
- SDA stuck low is not detected (only SCL stuck low / over-long stretch triggers the timeout).
- The slave needs a system clock of roughly 8x SCL or more (`quarter` >= 6 recommended; minimum 4).
- Protocol checks are procedural, not native SVA; cross coverage for error type x recovery is pending.
