`timescale 1ps/1ps
// Independent bus monitor: decodes START / repeated START / STOP and bytes (8 bits + ACK) from the SDA/SCL wires
// only. It never looks at any DUT state. Each decoded event increments evt_cnt AFTER evt_kind/evt_val/evt_nack are set.
//   evt_kind: 1 START, 2 repeated START, 3 STOP, 4 BYTE (evt_val = byte, evt_nack = ACK bit: 0 ACK, 1 NACK)
// proto_errors counts START/STOP conditions seen in the middle of a byte (SDA changing while SCL high).
// The SCL rising edge that precedes a legal STOP / repeated START is counted as a first "bit" (bitcnt = 1). A START/STOP
// after exactly one clock is physically identical to that legal case, so only bitcnt >= 2 is reported as an error.
// `enable` low clears the decoder (used around resets / aborted transactions).
module i2c_monitor (
    input  logic        sda,
    input  logic        scl,
    input  logic        enable,
    output reg [31:0]   evt_cnt,
    output reg [2:0]    evt_kind,
    output reg [7:0]    evt_val,
    output reg          evt_nack,
    output reg [31:0]   proto_errors
);
    reg        in_txn;
    integer    bitcnt;
    reg [7:0]  shreg;

    initial begin
        evt_cnt = 0; evt_kind = 0; evt_val = 0; evt_nack = 0; proto_errors = 0;
        in_txn = 0; bitcnt = 0; shreg = 0;
    end

    always @(negedge enable) begin in_txn = 0; bitcnt = 0; end

    always @(negedge sda) if (enable && scl === 1'b1) begin          // START / repeated START
        if (in_txn && bitcnt >= 2) proto_errors = proto_errors + 1;
        evt_kind = in_txn ? 3'd2 : 3'd1; evt_val = 0; evt_nack = 0;
        evt_cnt = evt_cnt + 1;
        in_txn = 1; bitcnt = 0;
    end

    always @(posedge sda) if (enable && scl === 1'b1) begin          // STOP
        if (in_txn) begin
            if (bitcnt >= 2) proto_errors = proto_errors + 1;
            evt_kind = 3'd3; evt_val = 0; evt_nack = 0;
            evt_cnt = evt_cnt + 1;
            in_txn = 0; bitcnt = 0;
        end
    end

    always @(posedge scl) if (enable && in_txn) begin               // sample on the rising edge of SCL
        if (bitcnt < 8) begin
            shreg = {shreg[6:0], sda}; bitcnt = bitcnt + 1;
        end else begin
            evt_val = shreg; evt_nack = sda; evt_kind = 3'd4;
            evt_cnt = evt_cnt + 1;
            bitcnt = 0;
        end
    end
endmodule
