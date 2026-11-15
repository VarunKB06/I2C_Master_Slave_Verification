// Slave register bank (8-bit registers).
//   0x00 DATA   RW  write sets STATUS.data_valid; a read clears it
//   0x01 STATUS RO  [0] data_valid  [1] invalid_access (sticky, cleared by reading STATUS)  [7:2] 0
//   0x02 CONTROL RW reset 0
//   0x03 ID     RO  ID_VALUE
//   other addresses: writes ignored, reads return 0x00; both set STATUS.invalid_access.
//   writes to STATUS/ID are ignored and set invalid_access.
module i2c_register_bank #(parameter logic [7:0] ID_VALUE = 8'hA5) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] rd_addr,          // combinational peek
    output logic [7:0] rd_data,
    input  logic       rd_strobe,        // side effects of a read that was just loaded
    input  logic [7:0] rd_strobe_addr,
    input  logic       wr_en,
    input  logic [7:0] wr_addr,
    input  logic [7:0] wr_data
);
    logic [7:0] data_reg, ctrl_reg;
    logic       data_valid, inv_access;

    always_comb begin
        case (rd_addr)
            8'h00:   rd_data = data_reg;
            8'h01:   rd_data = {6'b0, inv_access, data_valid};
            8'h02:   rd_data = ctrl_reg;
            8'h03:   rd_data = ID_VALUE;
            default: rd_data = 8'h00;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_reg <= '0; ctrl_reg <= '0; data_valid <= 1'b0; inv_access <= 1'b0;
        end else begin
            if (rd_strobe) begin
                case (rd_strobe_addr)
                    8'h00: data_valid <= 1'b0;
                    8'h01: inv_access <= 1'b0;
                    8'h02, 8'h03: ;
                    default: inv_access <= 1'b1;
                endcase
            end
            if (wr_en) begin
                case (wr_addr)
                    8'h00: begin data_reg <= wr_data; data_valid <= 1'b1; end
                    8'h02: ctrl_reg <= wr_data;
                    default: inv_access <= 1'b1;
                endcase
            end
        end
    end
endmodule
