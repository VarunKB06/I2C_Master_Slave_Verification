// Stage 3a: Standard Mode timing and clock stretching (T31, T35-T37). Included inside tb_i2c_system.
// Fast Mode (400 kHz) is NOT implemented and therefore not tested.
task run_timing_tests;
    time t1, t2;
    integer per, base, base_long;
    begin
        begin_test(31, "Standard Mode 100 kHz timing");
        sys_reset; set_speed(16'd125); timing_en = 1;          // 125 clocks/quarter at 50 MHz = 100 kHz
        fork
            begin reg_write(slave_addr, 8'h02, 8'h6B); reg_read(slave_addr, 8'h02, 2); end
            begin @(posedge scl); t1 = $time; @(posedge scl); t2 = $time; end
        join
        per = t2 - t1;
        check(per >= 9900000 && per <= 10200000, "SCL period 9.9-10.2 us (about 100 kHz)");
        check(rbuf[0] === 8'h6B, "data correct at 100 kHz");
        check(chk_fail == 0, "tLOW/tHIGH/START/STOP timing checks pass");
        timing_en = 0; set_speed(16'd10);
        end_test;

        begin_test(35, "clock stretching (short)");
        sys_reset; set_speed(16'd10); stretch_cycles = 16'd100; base = stretch_cnt;
        reg_write(slave_addr, 8'h02, 8'hE1); reg_read(slave_addr, 8'h02, 2);
        check(rbuf[0] === 8'hE1, "data correct with stretching");
        check(stretch_cnt > base, "stretching observed on the bus");
        stretch_cycles = 16'd0;
        end_test;

        begin_test(36, "long clock stretching");
        sys_reset; set_speed(16'd10); stretch_cycles = 16'd1500; base_long = long_stretch_cnt;
        reg_write(slave_addr, 8'h00, 8'h9D); reg_read(slave_addr, 8'h00, 1);
        check(rbuf[0] === 8'h9D, "data correct with long stretching");
        check(long_stretch_cnt > base_long, "long stretch observed on the bus");
        stretch_cycles = 16'd0;
        end_test;

        begin_test(37, "stretch release: normal speed again");
        sys_reset; set_speed(16'd10); stretch_cycles = 16'd0; base = stretch_cnt;
        reg_write(slave_addr, 8'h02, 8'h12); reg_read(slave_addr, 8'h02, 1);
        check(rbuf[0] === 8'h12, "transaction completes");
        check(stretch_cnt == base, "no stretching once the slave stops it");
        end_test;
    end
endtask
