// Stage 3b: error and recovery (T38/T45, T40, T44/T50, T46/T47). Included inside tb_i2c_system.
// Bus-clear (9 clock pulses) is NOT implemented: a slave left driving SDA is recovered by a system reset.
task run_error_tests;
    begin
        begin_test(44, "SCL held low: timeout, then recovery");
        sys_reset; set_speed(16'd10); timeout_limit = 16'd300;
        mon_en = 0; f_scl_low = 1;
        cmd(1, 1, 1, 0, 0, {slave_addr, 1'b0});
        check(last_timeout === 1'b1, "master reports timeout (SCL stuck low)");
        check(bus_active === 1'b0 && m_sda_oe === 1'b0 && m_scl_oe === 1'b0, "master released the bus after timeout");
        drv_abort_cleanup;
        f_scl_low = 0; wait_clk(200); timeout_limit = 16'd0; mon_en = 1;
        reg_write(slave_addr, 8'h02, 8'h2D); reg_read(slave_addr, 8'h02, 1);
        check(rbuf[0] === 8'h2D, "bus works again after the fault is removed");
        end_test;

        begin_test(38, "stretch longer than timeout + reset");
        sys_reset; set_speed(16'd10); stretch_cycles = 16'd5000; timeout_limit = 16'd500;
        cmd(1, 0, 1, 0, 0, {slave_addr, 1'b0});               // slave stretches after the 8th bit
        check(last_timeout === 1'b1, "master times out while the slave stretches");
        check(bus_active === 1'b0 && m_sda_oe === 1'b0 && m_scl_oe === 1'b0, "master released both lines");
        mon_en = 0; drv_abort_cleanup;
        wait_clk(6000);
        $display("   note: after the abort the slave still drives SDA low (sda=%b); recovered by reset", sda);
        stretch_cycles = 16'd0; timeout_limit = 16'd0;
        sys_reset;
        check(sda === 1'b1 && scl === 1'b1, "bus idle after reset recovery");
        reg_write(slave_addr, 8'h02, 8'h4E); reg_read(slave_addr, 8'h02, 1);
        check(rbuf[0] === 8'h4E, "transaction works after recovery");
        end_test;

        begin_test(40, "reset during a write transaction");
        sys_reset; set_speed(16'd10);
        cmd(1, 0, 1, 0, 0, {slave_addr, 1'b0});
        cmd_issue(0, 0, 1, 0, 0, 8'h02);                      // next byte; do not wait for it
        wait_clk(100);
        check(bus_active === 1'b1, "transaction is active before the reset");
        sys_reset;
        check(sda === 1'b1 && scl === 1'b1, "bus released after reset");
        check(cmd_ready === 1'b1 && bus_active === 1'b0, "master idle after reset");
        reg_write(slave_addr, 8'h02, 8'h71); reg_read(slave_addr, 8'h02, 1);
        check(rbuf[0] === 8'h71, "normal transaction after reset recovery");
        end_test;

        begin_test(47, "reset during a read transaction");
        sys_reset; set_speed(16'd10);
        cmd(1, 0, 1, 0, 0, {slave_addr, 1'b1});
        cmd_issue(0, 0, 0, 1, 1, 8'h00);                      // read byte; do not wait
        wait_clk(120);
        sys_reset;
        check(sda === 1'b1 && scl === 1'b1, "bus released after reset");
        check(cmd_ready === 1'b1 && bus_active === 1'b0, "master idle after reset");
        reg_read(slave_addr, 8'h03, 1);
        check(rbuf[0] === 8'hA5, "ID readable after reset recovery");
        end_test;
    end
endtask
