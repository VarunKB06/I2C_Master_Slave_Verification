`timescale 1ps/1ps
// PROCEDURAL protocol/timing checker (NOT native SystemVerilog Assertions; no SVA is used in this project yet).
// Works on the SDA/SCL wires only. Checks:
//   P1  SDA must not change while SCL is high except for START/STOP (reported by i2c_monitor.proto_errors)
//   P2  tLOW   >= T_LOW_MIN   (SCL low time)
//   P3  tHIGH  >= T_HIGH_MIN  (SCL high time, not counting START/STOP periods)
//   P4  START hold  tHD;STA >= T_HD_STA (SDA fall -> SCL fall)
//   P5  repeated-START setup tSU;STA >= T_SU_STA (SCL rise -> SDA fall)
//   P6  STOP setup  tSU;STO >= T_SU_STO (SCL rise -> SDA rise)
//   P7  bus free time tBUF  >= T_BUF (STOP -> next START)
// Timing checks run only when `timing_en` = 1 (the fast-simulation configuration is faster than Standard Mode).
// It also measures clock stretching: a low period longer than 3x nom_low_ps counts as a stretch, > 25x as long.
module i2c_protocol_checker #(
    parameter integer T_LOW_MIN  = 4700000,   // ps, Standard Mode
    parameter integer T_HIGH_MIN = 4000000,
    parameter integer T_HD_STA   = 4000000,
    parameter integer T_SU_STA   = 4700000,
    parameter integer T_SU_STO   = 4000000,
    parameter integer T_BUF      = 4700000
) (
    input  logic        sda,
    input  logic        scl,
    input  logic        enable,
    input  logic        timing_en,
    input  logic [31:0] nom_low_ps,
    output reg [31:0]   fail_count,
    output reg [31:0]   checks_run,
    output reg [31:0]   stretch_cnt,
    output reg [31:0]   long_stretch_cnt,
    output reg [31:0]   min_low_ps, min_high_ps
);
    time t_scl_rise, t_scl_fall, t_sda_fall, t_stop, d;
    reg  in_txn;

    task bad(input [8*80-1:0] m);
        begin fail_count = fail_count + 1; $display("[CHECK FAIL] (procedural) t=%0t %0s", $time, m); end
    endtask

    initial begin
        fail_count = 0; checks_run = 0; stretch_cnt = 0; long_stretch_cnt = 0; min_low_ps = 0; min_high_ps = 0;
        t_scl_rise = 0; t_scl_fall = 0; t_sda_fall = 0; t_stop = 0; in_txn = 0;
    end

    always @(negedge enable) begin t_scl_rise = 0; t_scl_fall = 0; t_sda_fall = 0; t_stop = 0; in_txn = 0; end

    always @(posedge scl) if (enable) begin
        if (t_scl_fall != 0) begin
            d = $time - t_scl_fall;
            checks_run = checks_run + 1;
            if (min_low_ps == 0 || d < min_low_ps) min_low_ps = d;
            if (timing_en && d < T_LOW_MIN) bad("P2 tLOW too short");
            if (nom_low_ps != 0 && d > nom_low_ps * 3)  stretch_cnt = stretch_cnt + 1;
            if (nom_low_ps != 0 && d > nom_low_ps * 25) long_stretch_cnt = long_stretch_cnt + 1;
        end
        t_scl_rise = $time;
    end

    always @(negedge scl) if (enable) begin
        if (t_scl_rise != 0) begin
            checks_run = checks_run + 1;
            if (t_sda_fall > t_scl_rise) begin                       // a START happened during this high period
                d = $time - t_sda_fall;
                if (timing_en && d < T_HD_STA) bad("P4 START hold time too short");
            end else begin
                d = $time - t_scl_rise;
                if (min_high_ps == 0 || d < min_high_ps) min_high_ps = d;
                if (timing_en && d < T_HIGH_MIN) bad("P3 tHIGH too short");
            end
        end
        t_scl_fall = $time;
    end

    always @(negedge sda) if (enable && scl === 1'b1) begin          // START / repeated START
        checks_run = checks_run + 1;
        if (in_txn) begin
            if (timing_en && t_scl_rise != 0 && ($time - t_scl_rise) < T_SU_STA) bad("P5 repeated-START setup too short");
        end else begin
            if (timing_en && t_stop != 0 && ($time - t_stop) < T_BUF) bad("P7 bus free time too short");
        end
        t_sda_fall = $time; in_txn = 1;
    end

    always @(posedge sda) if (enable && scl === 1'b1) begin          // STOP
        if (in_txn) begin
            checks_run = checks_run + 1;
            if (timing_en && t_scl_rise != 0 && ($time - t_scl_rise) < T_SU_STO) bad("P6 STOP setup too short");
            t_stop = $time; in_txn = 0;
        end
    end
endmodule
