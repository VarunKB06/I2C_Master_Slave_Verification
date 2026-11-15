# Verification plan and status

**Execution status:** all 32 implemented tests passed with seeds 1, 2 and 3 in GitHub Actions (Icarus Verilog); logs in
`reports/ci_logs/`. Rows marked "covered implicitly" / "checked in ..." are exercised by those runs with 0 scoreboard errors
and 0 checker failures; rows marked pending or not implemented were not run.

## Environment
Procedural SystemVerilog testbench (`verification/tb_i2c_system.sv`), open-drain bus model with pull-ups, independent
monitor, reference-model scoreboard, procedural protocol/timing checker (not native SVA), hand-written coverage.
Random numbers: `$random(seed)`, `+seed=N` (printed in the summary). Stages: 1 = basic, 2 = protocol + advanced
transactions, 3 = timing, stretching, errors, random. `+STAGE=0` runs everything.

## What the scoreboard checks
START / repeated START / STOP sequence against the driver's intent; address byte; address ACK only for the configured
address; write bytes and their ACK/NACK; every read byte against an independent register-bank model (0xFF when the slave
does not drive); master ACK/NACK; transaction completion. Missing or extra bus events are errors. Reset flushes the model.

## Test matrix (original plan IDs)
| ID | Description | Status | File | Result |
|---|---|---|---|---|
| T1 | initial reset | implemented | tests/basic_tests.sv | PASS (CI seeds 1-3) |
| T2 | bus idle | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T3/T4 | START / STOP generation | implemented (T3) | basic_tests.sv | PASS (CI seeds 1-3) |
| T5/T6 | address transmission, ACK | implemented (T5) | basic_tests.sv | PASS (CI seeds 1-3) |
| T7 | address NACK | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T8 | one-byte write | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T9 | one-byte read | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T10 | multiple-byte write | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T11/T12 | START / STOP timing | checked in T31 (timing checker) | timing_tests.sv | checked, 0 failures (CI) |
| T13/T14 | SDA stable while SCL high / changes while low | implemented (T13) via monitor | protocol_tests.sv | PASS (CI seeds 1-3) |
| T15 | MSB-first | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T16-T18 | ACK/NACK timing, ninth clock | covered implicitly by monitor + scoreboard in every test | - | checked, 0 failures (CI) |
| T19 | address mismatch | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T20 | data byte sequence | covered by scoreboard in every test | - | PASS (CI seeds 1-3) |
| T21 | multiple-byte read | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T22 | multiple-byte write | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T23 | repeated START, write pointer then read | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T24 | repeated START, write then write | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T25/T26 | master ACK / final NACK | implemented (in T21) | protocol_tests.sv | PASS (CI seeds 1-3) |
| T27 | slave NACK | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T28 | transaction termination | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T29 | back-to-back transactions | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T30 | different slave addresses | implemented | protocol_tests.sv | PASS (CI seeds 1-3) |
| T31 | Standard Mode 100 kHz | implemented | timing_tests.sv | PASS (CI seeds 1-3) |
| T32 | Fast Mode 400 kHz | **not implemented** | - | - |
| T33/T34 | SCL high / low time | checked in T31 (checker thresholds) | timing_tests.sv | checked, 0 failures (CI) |
| T35 | clock stretching | implemented | timing_tests.sv | PASS (CI seeds 1-3) |
| T36 | long clock stretching | implemented | timing_tests.sv | PASS (CI seeds 1-3) |
| T37 | stretch release | implemented | timing_tests.sv | PASS (CI seeds 1-3) |
| T38 | timeout during stretching | implemented (with reset recovery, T45) | error_tests.sv | PASS (CI seeds 1-3) |
| T39 | different system clock frequencies | pending (only `quarter` varied) | - | - |
| T40 | reset during active transaction | implemented | error_tests.sv | PASS (CI seeds 1-3) |
| T41-T43 | invalid address / NACK address / NACK data | covered by T7, T19, T27 | - | PASS (CI seeds 1-3) |
| T44 | bus held low | implemented (SCL only) | error_tests.sv | PASS (CI seeds 1-3) |
| T45 | timeout recovery | implemented (T44, T38) | error_tests.sv | PASS (CI seeds 1-3) |
| T46/T47 | reset during transmission / reception | implemented (T40 write, T47 read) | error_tests.sv | PASS (CI seeds 1-3) |
| T48 | incomplete transaction | pending | - | - |
| T49 | unexpected STOP | pending | - | - |
| T50 | recovery after error | implemented (end of T44, T38, T40, T47) | error_tests.sv | PASS (CI seeds 1-3) |
| T51 | random addresses | implemented | tests/random_tests.sv | PASS (CI seeds 1-3) |
| T52/T53/T54 | random data / reads / lengths | folded into T51, T55-T58 | random_tests.sv | PASS (CI seeds 1-3) |
| T55 | random ACK/NACK | implemented | random_tests.sv | PASS (CI seeds 1-3) |
| T56 | random clock stretching | implemented | random_tests.sv | PASS (CI seeds 1-3) |
| T57 | back-to-back random | implemented | random_tests.sv | PASS (CI seeds 1-3) |
| T58 | long random stress | implemented | random_tests.sv | PASS (CI seeds 1-3) |

## Coverage (hand-written, not code coverage)
25 event bins and 14 cross bins (direction x address response, data length x direction, repeated START x direction,
stretching x direction). CI result for seeds 1, 2 and 3: **EVENT 25 / 25, CROSS 14 / 14** (`reports/functional_coverage.txt`).
No bin was excluded. The first run reached 13 / 14 (write transaction with a repeated START); test T24 closed it.
Not implemented: error-type x recovery cross and any Fast Mode bin. Coverage is functional; it says nothing about RTL code
coverage.
