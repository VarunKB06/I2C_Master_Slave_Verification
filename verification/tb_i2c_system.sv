`timescale 1ps/1ps
// Procedural self-checking testbench for the I2C master + slave system.
//   +STAGE=0 (all) | 1 | 2 | 3     +seed=N     +vcd (write waveforms/tb_i2c_system.vcd)
// The bus is an open-drain model with pull-ups; the monitor/scoreboard/protocol checker only observe SDA/SCL.
module tb_i2c_system;
    localparam integer CLK_PS = 20000;                // 50 MHz system clock

    reg clk = 0, rst_n = 0;
    always #(CLK_PS / 2) clk = ~clk;

    // configuration
    reg [15:0] quarter = 16'd10;                      // system clocks per quarter SCL period
    reg [15:0] timeout_limit = 16'd0, stretch_cycles = 16'd0;
    reg [6:0]  slave_addr = 7'h50;
    reg        force_nack = 1'b0, f_sda_low = 1'b0, f_scl_low = 1'b0;
    reg        mon_en = 1'b0, timing_en = 1'b0, std_mode = 1'b0;

    // master command interface
    reg        cmd_valid = 0, cmd_start = 0, cmd_stop = 0, cmd_write = 0, cmd_read = 0, cmd_nack = 0;
    reg  [7:0] cmd_wdata = 0;
    wire       cmd_ready, done, slave_nack, timeout_err, illegal_cmd, busy, bus_active;
    wire [7:0] rdata;
    wire       m_sda_oe, m_scl_oe, s_sda_oe, s_scl_oe, sda, scl;

    i2c_master dut_m (.clk(clk), .rst_n(rst_n), .quarter(quarter), .timeout_limit(timeout_limit),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_start(cmd_start), .cmd_stop(cmd_stop),
        .cmd_write(cmd_write), .cmd_read(cmd_read), .cmd_nack(cmd_nack), .cmd_wdata(cmd_wdata),
        .done(done), .rdata(rdata), .slave_nack(slave_nack), .timeout_err(timeout_err),
        .illegal_cmd(illegal_cmd), .busy(busy), .bus_active(bus_active),
        .sda_in(sda), .scl_in(scl), .sda_oe(m_sda_oe), .scl_oe(m_scl_oe));

    i2c_slave dut_s (.clk(clk), .rst_n(rst_n), .slave_addr(slave_addr), .stretch_cycles(stretch_cycles),
        .force_nack_data(force_nack), .sda_in(sda), .scl_in(scl), .sda_oe(s_sda_oe), .scl_oe(s_scl_oe));

    i2c_bus_model bus (.m_sda_oe(m_sda_oe), .m_scl_oe(m_scl_oe), .s_sda_oe(s_sda_oe), .s_scl_oe(s_scl_oe),
        .f_sda_low(f_sda_low), .f_scl_low(f_scl_low), .sda(sda), .scl(scl));

    // ---------------- verification components (observe the bus only)
    wire [31:0] evt_cnt, proto_errors;
    wire [2:0]  evt_kind;
    wire [7:0]  evt_val;
    wire        evt_nack;
    i2c_monitor mon (.sda(sda), .scl(scl), .enable(mon_en), .evt_cnt(evt_cnt), .evt_kind(evt_kind),
                     .evt_val(evt_val), .evt_nack(evt_nack), .proto_errors(proto_errors));

    wire [31:0] sb_errors, sb_checks, sb_bytes, txn_cnt, sum_len;
    wire        last_pred_nack, sum_rw, sum_addr_nack, sum_data_nack, sum_data_ack, sum_m_ack, sum_m_nack, sum_rstart;
    wire [7:0]  sum_addr;
    scoreboard sb (.model_rst_n(rst_n), .dut_addr(slave_addr), .force_nack_data(force_nack),
        .evt_cnt(evt_cnt), .evt_kind(evt_kind), .evt_val(evt_val), .evt_nack(evt_nack),
        .errors(sb_errors), .checks(sb_checks), .bytes_seen(sb_bytes), .txn_cnt(txn_cnt),
        .last_pred_nack(last_pred_nack), .sum_rw(sum_rw), .sum_addr_nack(sum_addr_nack),
        .sum_data_nack(sum_data_nack), .sum_data_ack(sum_data_ack), .sum_m_ack(sum_m_ack),
        .sum_m_nack(sum_m_nack), .sum_rstart(sum_rstart), .sum_addr(sum_addr), .sum_len(sum_len));

    wire [31:0] nom_low_ps = 2 * quarter * CLK_PS;
    wire [31:0] chk_fail, chk_runs, stretch_cnt, long_stretch_cnt, min_low_ps, min_high_ps;
    i2c_protocol_checker chk (.sda(sda), .scl(scl), .enable(mon_en), .timing_en(timing_en), .nom_low_ps(nom_low_ps),
        .fail_count(chk_fail), .checks_run(chk_runs), .stretch_cnt(stretch_cnt),
        .long_stretch_cnt(long_stretch_cnt), .min_low_ps(min_low_ps), .min_high_ps(min_high_ps));

    coverage cov (.rst_n(rst_n), .txn_cnt(txn_cnt), .sum_rw(sum_rw), .sum_addr_nack(sum_addr_nack),
        .sum_data_nack(sum_data_nack), .sum_data_ack(sum_data_ack), .sum_m_ack(sum_m_ack), .sum_m_nack(sum_m_nack),
        .sum_rstart(sum_rstart), .sum_addr(sum_addr), .sum_len(sum_len), .stretch_cnt(stretch_cnt),
        .long_stretch_cnt(long_stretch_cnt), .std_mode(std_mode), .timeout_err(timeout_err),
        .bus_active(bus_active), .fault_active(f_sda_low | f_scl_low));

    // ---------------- bookkeeping
    integer seed, seed0, stage;
    integer tb_checks = 0, tb_errors = 0, tests_run = 0, tests_pass = 0, tests_fail = 0, err_base = 0, watchdog = 0;
    integer cur_id; reg [8*40-1:0] cur_name;

    function integer rnd(input integer m);
        begin rnd = {$random(seed)} % m; end
    endfunction

    task check(input cond, input [8*48-1:0] msg);
        begin
            tb_checks = tb_checks + 1;
            if (!cond) begin tb_errors = tb_errors + 1; $display("[TB FAIL] t=%0t %0s", $time, msg); end
        end
    endtask

    task wait_clk(input integer n); begin repeat (n) @(posedge clk); end endtask

    task set_speed(input [15:0] q);
        begin quarter = q; std_mode = (q == 16'd125); wait_clk(4); end
    endtask

    integer drv_in_txn = 0;               // used by the driver tasks

    task sys_reset;                       // asynchronous assert, synchronous release, then re-enable the monitor
        begin
            mon_en = 0; drv_in_txn = 0;
            #1000; rst_n = 0;
            wait_clk(6);
            @(posedge clk); rst_n <= 1;
            wait_clk(10);
            mon_en = 1;
        end
    endtask

    function integer errors_now(input integer dummy);
        begin errors_now = tb_errors + sb_errors + chk_fail + proto_errors; end
    endfunction

    task begin_test(input integer id, input [8*40-1:0] name);
        begin cur_id = id; cur_name = name; err_base = errors_now(0); $display("[T%0d] START %0s", id, name); end
    endtask

    task end_test;
        integer d;
        begin
            d = errors_now(0) - err_base;
            tests_run = tests_run + 1;
            if (d == 0) begin tests_pass = tests_pass + 1; $display("[T%0d] PASS  %0s", cur_id, cur_name); end
            else begin tests_fail = tests_fail + 1; $display("[T%0d] FAIL  %0s (%0d new errors)", cur_id, cur_name, d); end
        end
    endtask

    function run_stage(input integer s); begin run_stage = (stage == 0) || (stage == s); end endfunction

    `include "i2c_driver.sv"
    `include "basic_tests.sv"
    `include "protocol_tests.sv"
    `include "timing_tests.sv"
    `include "error_tests.sv"
    `include "random_tests.sv"

    task summary;
        reg ok;
        begin
            cov.report;
            $display("=== PROTOCOL CHECKER SUMMARY ===");
            $display("mode: PROCEDURAL checker (not native SVA)");
            $display("checker failures: %0d  (evaluations: %0d)", chk_fail, chk_runs);
            $display("monitor protocol errors: %0d", proto_errors);
            $display("min SCL low / high time seen (ps): %0d / %0d", min_low_ps, min_high_ps);
            $display("=== END ===");
            ok = (tests_run > 0) && (tests_fail == 0) && (sb_errors == 0) && (chk_fail == 0) &&
                 (proto_errors == 0) && (tb_errors == 0) && !watchdog;
            $display("=== SUMMARY ===");
            $display("seed: %0d   stage: %0d", seed0, stage);
            $display("total tests: %0d", tests_run);
            $display("passed tests: %0d", tests_pass);
            $display("failed tests: %0d", tests_fail);
            $display("total checks: %0d (tb %0d + scoreboard %0d)", tb_checks + sb_checks, tb_checks, sb_checks);
            $display("transactions completed: %0d, bytes compared: %0d", txn_cnt, sb_bytes);
            $display("protocol checker failures: %0d", chk_fail);
            $display("scoreboard errors: %0d", sb_errors);
            $display("functional EVENT bins covered: %0d / %0d", cov.evt_hit(0), cov.evt_total(0));
            $display("functional CROSS bins covered: %0d / %0d", cov.x_hit(0), cov.x_total(0));
            if (watchdog) $display("WATCHDOG TIMEOUT");
            $display("FINAL: %0s", ok ? "PASS" : "FAIL");
            $display("=== END ===");
        end
    endtask

    initial begin
        repeat (10000) #10_000_000;                     // 100 ms of simulated time
        watchdog = 1; $display("[WATCHDOG] simulation timeout"); summary; $finish;
    end

    initial begin
        if (!$value$plusargs("seed=%d", seed))   seed = 1;
        seed0 = seed;                                    // $random(seed) modifies seed; keep the requested value
        if (!$value$plusargs("STAGE=%d", stage)) stage = 0;
        if ($test$plusargs("vcd")) begin
            $dumpfile("waveforms/tb_i2c_system.vcd");
            $dumpvars(0, tb_i2c_system);
        end
        $display("=== tb_i2c_system: stage=%0d seed=%0d ===", stage, seed0);
        wait_clk(2);
        if (run_stage(1)) run_basic_tests;
        if (run_stage(2)) run_protocol_tests;
        if (run_stage(3)) begin run_timing_tests; run_error_tests; run_random_tests; end
        summary;
        $finish;
    end
endmodule
