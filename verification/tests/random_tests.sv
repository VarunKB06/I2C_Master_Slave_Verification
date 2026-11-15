// Stage 3c: reproducible randomized transactions (+seed=N). Included inside tb_i2c_system.
task rand_txns(input integer count, input integer p_match, input integer p_nack, input integer p_stretch);
    integer it, i, n, k;
    reg [6:0] a;
    begin
        for (it = 0; it < count; it = it + 1) begin
            stretch_cycles = (rnd(100) < p_stretch) ? (20 + rnd(200)) : 0;
            force_nack     = (rnd(100) < p_nack);
            a = (rnd(100) < p_match) ? slave_addr : rnd(128);
            n = 1 + rnd(5);
            k = rnd(3);
            if (k == 0) begin
                wbuf[0] = rnd(4);
                for (i = 1; i < 8; i = i + 1) wbuf[i] = rnd(256);
                wr_txn(a, n);
            end else if (k == 1) rd_txn(a, n);
            else reg_read(a, rnd(4), n);
        end
        stretch_cycles = 0; force_nack = 0;
    end
endtask

task run_random_tests;
    begin
        begin_test(51, "random addresses and data");
        sys_reset; set_speed(16'd10); rand_txns(40, 60, 0, 0); end_test;

        begin_test(55, "random ACK/NACK behaviour");
        sys_reset; set_speed(16'd10); rand_txns(40, 70, 30, 0); end_test;

        begin_test(56, "random clock stretching");
        sys_reset; set_speed(16'd10); rand_txns(40, 80, 0, 50); end_test;

        begin_test(57, "back-to-back random transactions");
        sys_reset; set_speed(16'd10); rand_txns(60, 90, 10, 20); end_test;

        begin_test(58, "long random protocol stress");
        sys_reset; set_speed(16'd10); rand_txns(150, 80, 10, 25); end_test;
    end
endtask
