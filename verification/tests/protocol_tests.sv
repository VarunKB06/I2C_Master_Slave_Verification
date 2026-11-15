// Stage 2: protocol and advanced transactions (T13-T15, T19-T30). Included inside tb_i2c_system.
task run_protocol_tests;
    integer i, e0, p0, a;
    begin
        begin_test(13, "SDA stability / protocol cleanliness");
        sys_reset; p0 = proto_errors;
        reg_write(slave_addr, 8'h02, 8'h3C);
        reg_read(slave_addr, 8'h00, 4);
        wr_txn(slave_addr ^ 7'h04, 1);
        check(proto_errors == p0, "no START/STOP seen in the middle of a byte");
        check(chk_fail == 0, "no protocol checker failure");
        end_test;

        begin_test(15, "MSB-first data patterns");
        sys_reset;
        reg_write(slave_addr, 8'h00, 8'h80); reg_read(slave_addr, 8'h00, 1); check(rbuf[0] === 8'h80, "0x80 round trip");
        reg_write(slave_addr, 8'h00, 8'h01); reg_read(slave_addr, 8'h00, 1); check(rbuf[0] === 8'h01, "0x01 round trip");
        reg_write(slave_addr, 8'h00, 8'hA5); reg_read(slave_addr, 8'h00, 1); check(rbuf[0] === 8'hA5, "0xA5 round trip");
        reg_write(slave_addr, 8'h00, 8'h5A); reg_read(slave_addr, 8'h00, 1); check(rbuf[0] === 8'h5A, "0x5A round trip");
        end_test;

        begin_test(19, "address mismatch leaves slave unchanged");
        sys_reset;
        reg_write(slave_addr, 8'h02, 8'h11);
        wbuf[0] = 8'h02; wbuf[1] = 8'hEE; wr_txn(slave_addr ^ 7'h01, 2);
        check(txn_addr_nack === 1'b1, "mismatching address NACKed");
        reg_read(slave_addr, 8'h02, 1);
        check(rbuf[0] === 8'h11, "CONTROL unchanged by the mismatched write");
        end_test;

        begin_test(21, "multiple-byte read (T21/T25/T26)");
        sys_reset;
        reg_write(slave_addr, 8'h02, 8'h77);
        reg_read(slave_addr, 8'h00, 4);
        check(rbuf[2] === 8'h77 && rbuf[3] === 8'hA5, "CONTROL and ID read sequentially");
        check(sum_m_ack === 1'b1 && sum_m_nack === 1'b1, "master ACKs bytes, NACKs the final byte");
        end_test;

        begin_test(22, "multi-byte write, RO regs ignored");
        sys_reset;
        wbuf[0] = 8'h02; wbuf[1] = 8'h44; wbuf[2] = 8'h99; wbuf[3] = 8'h98;     // CONTROL, then ID (RO) and invalid
        wr_txn(slave_addr, 4);
        reg_read(slave_addr, 8'h02, 2);
        check(rbuf[0] === 8'h44, "CONTROL written");
        check(rbuf[1] === 8'hA5, "ID unchanged by write to a read-only register");
        end_test;

        begin_test(23, "repeated START (write pointer, read)");
        sys_reset;
        reg_write(slave_addr, 8'h00, 8'hC6);
        reg_read(slave_addr, 8'h00, 1);
        check(sum_rstart === 1'b1, "a repeated START was used");
        check(rbuf[0] === 8'hC6, "data read after repeated START");
        end_test;

        begin_test(27, "slave NACK on data");
        sys_reset;
        reg_write(slave_addr, 8'h02, 8'h31);
        force_nack = 1;
        wbuf[0] = 8'h02; wbuf[1] = 8'h55; wbuf[2] = 8'h66; wr_txn(slave_addr, 3);
        check(sum_data_nack === 1'b1, "slave NACKed a data byte");
        force_nack = 0;
        reg_read(slave_addr, 8'h02, 1);
        check(rbuf[0] === 8'h31, "NACKed data was not stored");
        end_test;

        begin_test(28, "transaction termination without data");
        sys_reset;
        cmd(1, 0, 1, 0, 0, {slave_addr, 1'b0});
        cmd(0, 0, 1, 0, 0, 8'h02);
        cmd(0, 1, 1, 0, 0, 8'h5C);                  // last byte with STOP
        reg_read(slave_addr, 8'h02, 1);
        check(rbuf[0] === 8'h5C, "write ended by STOP took effect");
        end_test;

        begin_test(29, "back-to-back transactions");
        sys_reset;
        for (i = 0; i < 6; i = i + 1) begin
            reg_write(slave_addr, 8'h02, 8'h10 + i);
            reg_read(slave_addr, 8'h02, 1);
            check(rbuf[0] === 8'h10 + i, "value written in the previous transaction");
        end
        end_test;

        begin_test(30, "different slave addresses");
        sys_reset;
        for (i = 0; i < 4; i = i + 1) begin
            case (i) 0: a = 8'h08; 1: a = 8'h2A; 2: a = 8'h50; default: a = 8'h77; endcase
            slave_addr = a; wait_clk(10);
            reg_write(slave_addr, 8'h02, 8'hD0 + i);
            reg_read(slave_addr, 8'h02, 1);
            check(rbuf[0] === 8'hD0 + i, "register access at this address");
            wr_txn(slave_addr + 7'h01, 1);
            check(txn_addr_nack === 1'b1, "neighbouring address is not acknowledged");
        end
        slave_addr = 7'h50; wait_clk(10);
        end_test;
    end
endtask
