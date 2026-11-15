# Change log

## Waveform screenshots
- Added four GTKWave screenshots of the CI VCD under `waveforms/` and referenced them in the README.

## First passing CI (32 tests, seeds 1-3)
- Results, logs and report extracts committed under `reports/`; stage-1 VCD under `waveforms/`.
- README results, waveform section, verification plan and notes updated from the real logs.

## CI fix 1
- `i2c_monitor.sv`: the SCL edge before a legal STOP / repeated START was counted as a data bit, so every STOP was reported
  as "mid-byte" (29 of 31 tests failed in the first run; scoreboard and checker errors were 0). Now only START/STOP after
  two or more clocks in a byte is reported.
- Added test T24 (repeated START, write then write) to close the last cross bin.
