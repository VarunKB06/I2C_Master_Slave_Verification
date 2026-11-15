# Implementation notes and deviations from the original plan
- **Byte-command master** instead of a transaction-level FSM: the driver sequences START, address, data and STOP;
  this keeps the bit engine shared and every FSM transition observable on the bus.
- **`i2c_bus_model` module instead of `i2c_bus_if` interface**: Icarus Verilog does not support SystemVerilog interfaces.
- **No `i2c_shift_register` / `i2c_bit_counter` modules**: shifting and counting are inline in the master and slave.
- **Procedural protocol checker, no native SVA**: the SDA/SCL conditions are asynchronous events; the checker uses
  event-driven procedural code and is labelled as such. A native-SVA version is future work.
- **Scoreboard** gets intent from the driver (`exp_push`) and observed events from the monitor; reads are predicted by an
  independent register-bank model. DUT state is never used.
- **Timeout** covers an over-long stretch or SCL held low. **No bus-clear**; test T38 recovers with a system reset and
  prints the observation that the slave keeps SDA low after the abort.
- Timing numbers are derived from the tick structure (see architecture.md) and are only claimed once the checker passes in CI.
- Testbench conventions inherited from earlier projects: `timescale` in every verification file, no SystemVerilog strings
  in tasks, packed message vectors, explicit array bounds, waveform only with `+vcd`.
- **Monitor mid-byte check:** the SCL rising edge before a legal STOP / repeated START looks like a first data clock, so the
  monitor reports a START/STOP only as "mid-byte" after 2 or more clocks. A START/STOP after exactly one clock is
  physically indistinguishable from the legal case and is accepted. (A first version flagged every STOP; the first CI run
  showed this as a false positive, with scoreboard and checker errors at 0.)
