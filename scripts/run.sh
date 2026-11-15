#!/bin/sh
# usage (from repo root):  bash scripts/run.sh <stage 0|1|2|3> [iverilog|riviera]
#   env: SEED=<n> (default 1)   WAVES=0|1 (default 0; 1 writes waveforms/tb_i2c_system.vcd)
# stage 0 = every test in one simulation (also writes reports/*.txt).
# Exit status: 0 only if the simulation compiled, ran, printed "FINAL: PASS" and reported no error lines.
STAGE=${1:-0}; SIM=${2:-iverilog}; SEED=${SEED:-1}; WAVES=${WAVES:-0}
mkdir -p reports build waveforms
SRC="rtl/i2c_clock_gen.sv rtl/i2c_timeout_monitor.sv rtl/i2c_start_stop_detector.sv rtl/i2c_address_decoder.sv rtl/i2c_register_bank.sv rtl/i2c_master.sv rtl/i2c_slave.sv verification/i2c_bus_model.sv verification/i2c_monitor.sv verification/scoreboard.sv verification/assertions.sv verification/coverage.sv verification/tb_i2c_system.sv"
LOG=reports/run_stage${STAGE}.log
: > "$LOG"
PLUS="+STAGE=$STAGE +seed=$SEED"; [ "$WAVES" = "1" ] && PLUS="$PLUS +vcd"

case "$SIM" in
  iverilog)
    command -v iverilog >/dev/null 2>&1 || { echo "ERROR: iverilog not found" | tee -a "$LOG"; exit 3; }
    { echo "simulator: $(iverilog -V 2>&1 | head -1)"; echo "seed: $SEED  stage: $STAGE"; } >> "$LOG"
    if ! iverilog -g2012 -Wall -s tb_i2c_system -I verification -I verification/tests -o build/sim_$STAGE.out $SRC >> "$LOG" 2>&1; then
      echo "COMPILE FAILED (see $LOG)"; tail -20 "$LOG"; exit 1
    fi
    vvp build/sim_$STAGE.out $PLUS >> "$LOG" 2>&1; SIM_RC=$? ;;
  riviera)
    command -v vsim >/dev/null 2>&1 || { echo "ERROR: vsim not found" | tee -a "$LOG"; exit 3; }
    vlib build/work >> "$LOG" 2>&1
    if ! vlog -sv2k12 +incdir+verification +incdir+verification/tests -work build/work $SRC >> "$LOG" 2>&1; then
      echo "COMPILE FAILED (see $LOG)"; tail -20 "$LOG"; exit 1
    fi
    vsim -c -lib build/work tb_i2c_system $PLUS -do "run -all; quit -code 0" >> "$LOG" 2>&1; SIM_RC=$? ;;
  *) echo "unknown simulator '$SIM'"; exit 2 ;;
esac

grep -E "^\[T[0-9]+\] (PASS|FAIL)|FINAL:|SB ERROR|TB FAIL|CHECK FAIL|WATCHDOG|ERROR" "$LOG"
if [ "$STAGE" = "0" ]; then
  sed -n '/=== SUMMARY/,/=== END/p'                 "$LOG" > reports/simulation_summary.txt
  sed -n '/=== PROTOCOL CHECKER SUMMARY/,/=== END/p' "$LOG" > reports/protocol_checker_summary.txt
  sed -n '/=== FUNCTIONAL COVERAGE/,/=== END/p'     "$LOG" > reports/functional_coverage.txt
fi
[ "$SIM_RC" -eq 0 ] || { echo "simulator exited with status $SIM_RC"; exit 1; }
grep -q "FINAL: " "$LOG"      || { echo "no FINAL line: simulation did not complete"; exit 1; }
grep -q "FINAL: PASS" "$LOG"  || { echo "REGRESSION FAILED (stage $STAGE)"; exit 1; }
echo "stage $STAGE: PASS"
