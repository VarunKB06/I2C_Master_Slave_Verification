`timescale 1ps/1ps
// Reference model + scoreboard. Inputs are the events decoded by i2c_monitor from the real SDA/SCL wires, plus the
// intent the test driver registered with exp_push() BEFORE issuing each command. It never uses DUT FSM state.
//   * compares every observed event (START / repeated START / STOP / byte) with the expected sequence
//   * checks address decoding, ACK/NACK of address and data, write data ordering, master ACK/NACK
//   * keeps an independent model of the slave register bank (pointer + auto-increment) and predicts every read byte
//     (0xFF when the slave does not drive SDA)
// Expected kinds: 1 START, 2 repeated START, 3 STOP, 4 address byte, 5 write byte, 6 read byte (exp_nack = master NACK)
module scoreboard #(parameter logic [7:0] ID_VALUE = 8'hA5) (
    input  logic        model_rst_n,
    input  logic [6:0]  dut_addr,
    input  logic        force_nack_data,
    input  logic [31:0] evt_cnt,
    input  logic [2:0]  evt_kind,
    input  logic [7:0]  evt_val,
    input  logic        evt_nack,
    output reg [31:0]   errors, checks, bytes_seen, txn_cnt,
    output reg          last_pred_nack,
    // summary of the last completed transaction (valid when txn_cnt changes)
    output reg          sum_rw, sum_addr_nack, sum_data_nack, sum_data_ack, sum_m_ack, sum_m_nack, sum_rstart,
    output reg [7:0]    sum_addr,
    output reg [31:0]   sum_len
);
    localparam integer N = 4096;
    integer     exp_kind [0:N-1];
    reg [7:0]   exp_val  [0:N-1];
    integer     exp_nack [0:N-1];
    integer     exp_wr, exp_rd;

    // slave-register reference model
    reg [7:0] m_data, m_ctrl, m_ptr;
    reg       m_valid, m_inv;
    // transaction state
    reg       in_txn, matched, rw, first_byte, nacked, rd_active;
    integer   seg_idx, ek, en, ndata;
    reg [7:0] ev, pv;
    reg       pred_nack;

    task err(input [8*80-1:0] m);
        begin errors = errors + 1; $display("[SB ERROR] t=%0t %0s", $time, m); end
    endtask

    task exp_push(input integer kind, input [7:0] val, input integer nack);
        begin
            exp_kind[exp_wr % N] = kind; exp_val[exp_wr % N] = val; exp_nack[exp_wr % N] = nack;
            exp_wr = exp_wr + 1;
        end
    endtask

    task exp_flush; begin exp_rd = exp_wr; end endtask

    task model_reset;
        begin
            m_data = 0; m_ctrl = 0; m_ptr = 0; m_valid = 0; m_inv = 0;
            in_txn = 0; matched = 0; rw = 0; first_byte = 0; nacked = 0; rd_active = 0; seg_idx = 0; ndata = 0;
        end
    endtask

    task model_write(input [7:0] v);
        begin
            if (first_byte) begin m_ptr = v; first_byte = 0; end
            else begin
                case (m_ptr)
                    8'h00:   begin m_data = v; m_valid = 1; end
                    8'h02:   m_ctrl = v;
                    default: m_inv = 1;
                endcase
                m_ptr = m_ptr + 1;
            end
        end
    endtask

    task model_read;
        begin
            case (m_ptr)
                8'h00:   begin pv = m_data; m_valid = 0; end
                8'h01:   begin pv = {6'b0, m_inv, m_valid}; m_inv = 0; end
                8'h02:   pv = m_ctrl;
                8'h03:   pv = ID_VALUE;
                default: begin pv = 8'h00; m_inv = 1; end
            endcase
            m_ptr = m_ptr + 1;
        end
    endtask

    initial begin
        errors = 0; checks = 0; bytes_seen = 0; txn_cnt = 0; exp_wr = 0; exp_rd = 0; last_pred_nack = 0;
        sum_rw = 0; sum_addr_nack = 0; sum_data_nack = 0; sum_data_ack = 0; sum_m_ack = 0; sum_m_nack = 0;
        sum_rstart = 0; sum_addr = 0; sum_len = 0;
        model_reset;
    end

    // system reset: the slave's registers and any transaction in flight are gone
    always @(negedge model_rst_n) begin
        model_reset; exp_rd = exp_wr;
    end

    always @(evt_cnt) if (model_rst_n && evt_cnt != 0) begin
        checks = checks + 1;
        if (exp_rd == exp_wr) err("unexpected bus event (nothing expected)");
        else begin
            ek = exp_kind[exp_rd % N]; ev = exp_val[exp_rd % N]; en = exp_nack[exp_rd % N];
            exp_rd = exp_rd + 1;
            case (evt_kind)
            3'd1: begin                                              // START
                if (ek != 1) err("START seen but another event expected");
                in_txn = 1; seg_idx = 0; ndata = 0; sum_rstart = 0;
                sum_addr_nack = 0; sum_data_nack = 0; sum_data_ack = 0; sum_m_ack = 0; sum_m_nack = 0;
            end
            3'd2: begin                                              // repeated START
                if (ek != 2) err("repeated START seen but another event expected");
                if (!in_txn) err("repeated START outside a transaction");
                seg_idx = 0; sum_rstart = 1;
            end
            3'd3: begin                                              // STOP
                if (ek != 3) err("STOP seen but another event expected");
                if (!in_txn) err("STOP outside a transaction");
                in_txn = 0;
                sum_len = ndata; sum_rw = rw; txn_cnt = txn_cnt + 1;
            end
            3'd4: begin                                              // byte (8 bits + ACK)
                bytes_seen = bytes_seen + 1; checks = checks + 1;
                if (!in_txn) err("byte outside a transaction");
                if (seg_idx == 0) begin                              // address + R/W
                    if (ek != 4) err("address byte seen but another event expected");
                    else if (evt_val !== ev) err("address byte differs from the one sent by the master");
                    matched = (evt_val[7:1] == dut_addr); rw = evt_val[0]; sum_addr = {1'b0, evt_val[7:1]};
                    pred_nack = !matched; last_pred_nack = pred_nack;
                    if (evt_nack !== pred_nack) err("address ACK/NACK wrong (slave must ACK only its own address)");
                    first_byte = matched && !rw; nacked = 0; rd_active = matched && rw;
                    sum_addr_nack = pred_nack;
                end else if (!rw) begin                              // data byte written by the master
                    if (ek != 5) err("write byte seen but another event expected");
                    else if (evt_val !== ev) err("write byte differs from the one sent by the master");
                    if (matched && !nacked) begin
                        pred_nack = force_nack_data;
                        model_write(evt_val);
                        if (force_nack_data) nacked = 1;
                    end else pred_nack = 1;
                    last_pred_nack = pred_nack;
                    if (evt_nack !== pred_nack) err("write data ACK/NACK wrong");
                    if (pred_nack) sum_data_nack = 1; else sum_data_ack = 1;
                    ndata = ndata + 1;
                end else begin                                       // data byte read by the master
                    if (ek != 6) err("read byte seen but another event expected");
                    if (matched && rd_active) model_read; else pv = 8'hFF;
                    if (evt_val !== pv) begin
                        err("read data differs from the reference model");
                        $display("          got 0x%0h expected 0x%0h", evt_val, pv);
                    end
                    if (evt_nack !== (en != 0)) err("master ACK/NACK differs from the command");
                    if (evt_nack) begin rd_active = 0; sum_m_nack = 1; end else sum_m_ack = 1;
                    ndata = ndata + 1;
                end
                seg_idx = seg_idx + 1;
            end
            default: err("unknown monitor event");
            endcase
        end
    end
endmodule
