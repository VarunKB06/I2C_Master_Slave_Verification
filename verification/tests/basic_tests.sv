// Stage 1: T1-T10 (basic bus operations). Included inside tb_i2c_system.
task run_basic_tests;
    integer e0;
    begin
        begin_test(1, "initial reset and idle state");
        sys_reset;
        check(sda === 1'b1 && scl === 1'b1, "SDA and SCL high after reset");
        check(cmd_ready === 1'b1 && busy === 1'b0 && bus_active === 1'b0, "master idle after reset");
        end_test;

        begin_test(2, "bus idle: no events, lines high");
        sys_reset; e0 = evt_cnt;
        wait_clk(3000);
        check(evt_cnt == e0, "no START/STOP/byte while idle");
        check(sda === 1'b1 && scl === 1'b1, "lines stay high");
        end_test;

        begin_test(3, "START and STOP generation");
        sys_reset; e0 = evt_cnt;
        wr_txn(slave_addr, 0);                       // START, address+W, STOP
        check(evt_cnt - e0 == 3, "START, address byte and STOP observed");
        check(txn_addr_nack === 1'b0, "address ACKed");
        end_test;

        begin_test(5, "address transmission + ACK (T5/T6)");
        sys_reset;
        wr_txn(slave_addr, 0);
        check(txn_addr_nack === 1'b0, "slave ACKs its own address");
        rd_txn(slave_addr, 1);
        check(txn_addr_nack === 1'b0, "slave ACKs its own address (read)");
        end_test;

        begin_test(7, "address NACK");
        sys_reset;
        wr_txn(slave_addr ^ 7'h01, 0);
        check(txn_addr_nack === 1'b1, "non-matching address is NACKed");
        rd_txn(slave_addr ^ 7'h20, 1);
        check(txn_addr_nack === 1'b1, "non-matching read address NACKed");
        end_test;

        begin_test(8, "one-byte write");
        sys_reset;
        reg_write(slave_addr, 8'h00, 8'h5A);
        check(txn_addr_nack === 1'b0, "write transaction acknowledged");
        reg_read(slave_addr, 8'h00, 1);
        check(rbuf[0] === 8'h5A, "DATA reads back the written value");
        end_test;

        begin_test(9, "one-byte read (ID register)");
        sys_reset;
        reg_read(slave_addr, 8'h03, 1);
        check(rbuf[0] === 8'hA5, "ID register reads 0xA5");
        end_test;

        begin_test(10, "multiple-byte write + read back");
        sys_reset;
        wbuf[0] = 8'h00; wbuf[1] = 8'hA1; wbuf[2] = 8'hB2; wbuf[3] = 8'hC3;   // ptr=0: DATA, STATUS(RO), CONTROL
        wr_txn(slave_addr, 4);
        reg_read(slave_addr, 8'h00, 4);
        check(rbuf[0] === 8'hA1, "DATA = 0xA1");
        check(rbuf[1] === 8'h02, "STATUS: invalid_access set, data_valid clear");
        check(rbuf[2] === 8'hC3, "CONTROL = 0xC3");
        check(rbuf[3] === 8'hA5, "ID = 0xA5");
        end_test;
    end
endtask
