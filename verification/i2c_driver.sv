// Driver tasks, `included inside tb_i2c_system (uses its signals). Every command first registers its expected bus
// events with the scoreboard (sb.exp_push), then hands the command to the master. Addresses are 7-bit.
integer cmd_guard  = 400000;                 // clock cycles to wait for a command to finish
reg [7:0] last_rdata;
reg       last_slave_nack, last_timeout, last_illegal, cmd_hung, txn_addr_nack;
reg [7:0] wbuf [0:63];
reg [7:0] rbuf [0:63];

task cmd_issue(input s, input p, input w, input r, input nk, input [7:0] d);
    begin
        if (s) sb.exp_push(drv_in_txn ? 2 : 1, 8'h00, 0);
        if (w) sb.exp_push(s ? 4 : 5, d, 0);
        if (r) sb.exp_push(6, 8'h00, nk);
        if (p) sb.exp_push(3, 8'h00, 0);
        if (p) drv_in_txn = 0; else if (s) drv_in_txn = 1;
        while (!cmd_ready) @(posedge clk);
        @(posedge clk);
        cmd_valid <= 1; cmd_start <= s; cmd_stop <= p; cmd_write <= w; cmd_read <= r; cmd_nack <= nk; cmd_wdata <= d;
        @(posedge clk);
        cmd_valid <= 0; cmd_start <= 0; cmd_stop <= 0; cmd_write <= 0; cmd_read <= 0; cmd_nack <= 0;
    end
endtask

task cmd_wait;
    integer n;
    begin
        n = 0;
        while (!done && n < cmd_guard) begin @(posedge clk); n = n + 1; end
        cmd_hung = (n >= cmd_guard);
        last_rdata = rdata; last_slave_nack = slave_nack; last_timeout = timeout_err; last_illegal = illegal_cmd;
        if (cmd_hung) begin tb_errors = tb_errors + 1; $display("[TB FAIL] t=%0t command did not finish", $time); end
    end
endtask

task cmd(input s, input p, input w, input r, input nk, input [7:0] d);
    begin
        cmd_issue(s, p, w, r, nk, d);
        cmd_wait;
        if (w && !cmd_hung && !last_timeout && !last_illegal)
            check(last_slave_nack === sb.last_pred_nack, "slave_nack equals the predicted ACK/NACK");
    end
endtask

task drv_abort_cleanup;                       // after a timeout / reset: forget what was expected
    begin drv_in_txn = 0; sb.exp_flush; end
endtask

task wr_txn(input [6:0] a, input integer n);  // START, address+W, wbuf[0..n-1], STOP
    integer i; reg stopped;
    begin
        cmd(1, 0, 1, 0, 0, {a, 1'b0});
        txn_addr_nack = last_slave_nack;
        if (last_timeout) drv_abort_cleanup;
        else if (last_slave_nack || n == 0) cmd(0, 1, 0, 0, 0, 8'h00);
        else begin
            stopped = 0;
            for (i = 0; i < n && !stopped; i = i + 1) begin
                cmd(0, (i == n - 1), 1, 0, 0, wbuf[i]);
                if (last_timeout) begin drv_abort_cleanup; stopped = 1; end
                else if (last_slave_nack && i != n - 1) begin cmd(0, 1, 0, 0, 0, 8'h00); stopped = 1; end
            end
        end
    end
endtask

task rd_txn(input [6:0] a, input integer n);  // START, address+R, n reads (ACK ... NACK), STOP -> rbuf
    integer i;
    begin
        cmd(1, 0, 1, 0, 0, {a, 1'b1});
        txn_addr_nack = last_slave_nack;
        if (last_timeout) drv_abort_cleanup;
        else if (last_slave_nack) cmd(0, 1, 0, 0, 0, 8'h00);
        else for (i = 0; i < n; i = i + 1) begin
            cmd(0, (i == n - 1), 0, 1, (i == n - 1), 8'h00);
            rbuf[i] = last_rdata;
        end
    end
endtask

task reg_write(input [6:0] a, input [7:0] reg_ptr, input [7:0] val);
    begin wbuf[0] = reg_ptr; wbuf[1] = val; wr_txn(a, 2); end
endtask

task reg_read(input [6:0] a, input [7:0] reg_ptr, input integer n);   // write pointer, repeated START, read n bytes
    integer i;
    begin
        cmd(1, 0, 1, 0, 0, {a, 1'b0});
        txn_addr_nack = last_slave_nack;
        if (last_timeout) drv_abort_cleanup;
        else if (last_slave_nack) cmd(0, 1, 0, 0, 0, 8'h00);
        else begin
            cmd(0, 0, 1, 0, 0, reg_ptr);
            if (last_timeout) drv_abort_cleanup;
            else rd_txn(a, n);
        end
    end
endtask
