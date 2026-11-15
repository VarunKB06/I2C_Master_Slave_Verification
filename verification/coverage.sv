`timescale 1ps/1ps
// Hand-written functional coverage (event bins and cross bins, reported separately). NOT RTL code coverage and
// NOT covergroup coverage. Fast Mode is not implemented, so there is no Fast Mode bin. Every bit vector has exactly
// one writer process.
module coverage (
    input  logic        rst_n,
    input  logic [31:0] txn_cnt,
    input  logic        sum_rw, sum_addr_nack, sum_data_nack, sum_data_ack, sum_m_ack, sum_m_nack, sum_rstart,
    input  logic [7:0]  sum_addr,
    input  logic [31:0] sum_len,
    input  logic [31:0] stretch_cnt, long_stretch_cnt,
    input  logic        std_mode,         // 1 while Standard Mode timing (100 kHz) is configured
    input  logic        timeout_err,
    input  logic        bus_active,
    input  logic        fault_active
);
    localparam integer NB = 25;
    localparam integer B_START=0, B_RSTART=1, B_STOP=2, B_WRITE=3, B_READ=4, B_SINGLE=5, B_MULTI=6, B_MATCH=7,
                       B_MISMATCH=8, B_ADDR_LO=9, B_ADDR_MID=10, B_ADDR_HI=11, B_ADDR_ACK=12, B_ADDR_NACK=13,
                       B_DATA_ACK=14, B_DATA_NACK=15, B_M_ACK=16, B_M_NACK=17, B_STD=18, B_STRETCH=19,
                       B_LSTRETCH=20, B_TIMEOUT=21, B_STUCK=22, B_RST_TXN=23, B_RECOV=24;

    reg [NB-1:0] ev_t = 0, ev_to = 0, ev_rs = 0;     // writers: txn monitor / timeout monitor / reset monitor
    reg [3:0]    x_dir_ack = 0;                      // X1 direction x address ACK/NACK
    reg [5:0]    x_len_dir = 0;                      // X2 data length class (1,2,>2) x direction
    reg [1:0]    x_rs_dir = 0;                       // X3 repeated START x direction
    reg [1:0]    x_str_dir = 0;                      // X4 clock stretching x direction
    wire [NB-1:0] ev = ev_t | ev_to | ev_rs;

    integer last_stretch = 0, last_long = 0, seen_to = 0, seen_rs = 0, gen_to = 0, gen_rs = 0, lc;
    reg st, lst;

    always @(txn_cnt) if (txn_cnt != 0) begin
        ev_t[B_START] = 1; ev_t[B_STOP] = 1;
        if (sum_rw) ev_t[B_READ] = 1; else ev_t[B_WRITE] = 1;
        if (sum_len == 1) ev_t[B_SINGLE] = 1;
        if (sum_len > 1)  ev_t[B_MULTI] = 1;
        if (sum_rstart)   ev_t[B_RSTART] = 1;
        if (sum_addr_nack) begin ev_t[B_MISMATCH] = 1; ev_t[B_ADDR_NACK] = 1; end
        else               begin ev_t[B_MATCH] = 1;    ev_t[B_ADDR_ACK] = 1; end
        if (sum_addr < 8'h20) ev_t[B_ADDR_LO] = 1;
        else if (sum_addr < 8'h60) ev_t[B_ADDR_MID] = 1;
        else ev_t[B_ADDR_HI] = 1;
        if (sum_data_ack)  ev_t[B_DATA_ACK] = 1;
        if (sum_data_nack) ev_t[B_DATA_NACK] = 1;
        if (sum_m_ack)     ev_t[B_M_ACK] = 1;
        if (sum_m_nack)    ev_t[B_M_NACK] = 1;
        if (std_mode)      ev_t[B_STD] = 1;
        st  = (stretch_cnt != last_stretch);      last_stretch = stretch_cnt;
        lst = (long_stretch_cnt != last_long);    last_long = long_stretch_cnt;
        if (st)  ev_t[B_STRETCH] = 1;
        if (lst) ev_t[B_LSTRETCH] = 1;
        if (gen_to + gen_rs != seen_to + seen_rs) begin ev_t[B_RECOV] = 1; seen_to = gen_to; seen_rs = gen_rs; end
        // crosses
        x_dir_ack[(sum_rw ? 2 : 0) + (sum_addr_nack ? 1 : 0)] = 1;
        lc = (sum_len <= 1) ? 0 : ((sum_len == 2) ? 1 : 2);
        if (sum_len >= 1) x_len_dir[lc * 2 + (sum_rw ? 1 : 0)] = 1;
        if (sum_rstart) x_rs_dir[sum_rw ? 1 : 0] = 1;
        if (st) x_str_dir[sum_rw ? 1 : 0] = 1;
    end

    always @(posedge timeout_err) begin
        ev_to[B_TIMEOUT] = 1;
        if (fault_active) ev_to[B_STUCK] = 1;
        gen_to = gen_to + 1;
    end

    always @(negedge rst_n) begin
        if (bus_active) begin ev_rs[B_RST_TXN] = 1; gen_rs = gen_rs + 1; end
    end

    function integer count_bits(input [63:0] v, input integer n);
        integer i, c;
        begin c = 0; for (i = 0; i < n; i = i + 1) if (v[i]) c = c + 1; count_bits = c; end
    endfunction

    function integer evt_total(input integer dummy); begin evt_total = NB; end endfunction
    function integer evt_hit(input integer dummy); begin evt_hit = count_bits({{(64-NB){1'b0}}, ev}, NB); end endfunction
    function integer x_total(input integer dummy); begin x_total = 4 + 6 + 2 + 2; end endfunction
    function integer x_hit(input integer dummy);
        begin x_hit = count_bits({60'b0, x_dir_ack}, 4) + count_bits({58'b0, x_len_dir}, 6)
                    + count_bits({62'b0, x_rs_dir}, 2) + count_bits({62'b0, x_str_dir}, 2); end
    endfunction

    task pr(input integer idx, input [8*64-1:0] name);
        begin $display("  [%s] %0s", ev[idx] ? "HIT " : "MISS", name); end
    endtask

    task report;
        begin
            $display("=== FUNCTIONAL COVERAGE (hand-written bins; not code coverage, not covergroups) ===");
            $display("-- EVENT BINS --");
            pr(B_START,"transaction: START");            pr(B_STOP,"transaction: STOP");
            pr(B_RSTART,"transaction: repeated START");  pr(B_WRITE,"transaction: write");
            pr(B_READ,"transaction: read");              pr(B_SINGLE,"transfer: single data byte");
            pr(B_MULTI,"transfer: multiple data bytes"); pr(B_MATCH,"address: matching");
            pr(B_MISMATCH,"address: non-matching");      pr(B_ADDR_LO,"address value: 0x00-0x1F");
            pr(B_ADDR_MID,"address value: 0x20-0x5F");   pr(B_ADDR_HI,"address value: 0x60-0x7F");
            pr(B_ADDR_ACK,"ack: address ACK");           pr(B_ADDR_NACK,"ack: address NACK");
            pr(B_DATA_ACK,"ack: slave ACKs write data"); pr(B_DATA_NACK,"ack: slave NACKs write data");
            pr(B_M_ACK,"ack: master ACK after read");    pr(B_M_NACK,"ack: master NACK after read");
            pr(B_STD,"timing: Standard Mode 100 kHz");   pr(B_STRETCH,"timing: clock stretching");
            pr(B_LSTRETCH,"timing: long clock stretching"); pr(B_TIMEOUT,"error: master timeout");
            pr(B_STUCK,"error: bus stuck low");          pr(B_RST_TXN,"error: reset during transaction");
            pr(B_RECOV,"error: recovery (txn after timeout/reset)");
            $display("EVENT BINS COVERED: %0d / %0d", evt_hit(0), evt_total(0));
            $display("-- CROSS BINS --");
            $display(" X1 direction x address response");
            $display("   write: ACK:%s NACK:%s", x_dir_ack[0]?"HIT ":"MISS", x_dir_ack[1]?"HIT ":"MISS");
            $display("   read : ACK:%s NACK:%s", x_dir_ack[2]?"HIT ":"MISS", x_dir_ack[3]?"HIT ":"MISS");
            $display(" X2 data length x direction (w/r)");
            $display("   1 byte : w:%s r:%s", x_len_dir[0]?"HIT ":"MISS", x_len_dir[1]?"HIT ":"MISS");
            $display("   2 bytes: w:%s r:%s", x_len_dir[2]?"HIT ":"MISS", x_len_dir[3]?"HIT ":"MISS");
            $display("   >2     : w:%s r:%s", x_len_dir[4]?"HIT ":"MISS", x_len_dir[5]?"HIT ":"MISS");
            $display(" X3 repeated START x direction of the transaction");
            $display("   write: %s  read: %s", x_rs_dir[0]?"HIT ":"MISS", x_rs_dir[1]?"HIT ":"MISS");
            $display(" X4 clock stretching x direction");
            $display("   write: %s  read: %s", x_str_dir[0]?"HIT ":"MISS", x_str_dir[1]?"HIT ":"MISS");
            $display("CROSS BINS COVERED: %0d / %0d", x_hit(0), x_total(0));
            $display("NOT IMPLEMENTED: error-type x recovery cross, Fast Mode bins");
            $display("=== END ===");
        end
    endtask
endmodule
