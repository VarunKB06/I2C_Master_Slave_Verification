// I2C slave with a small register bank behind a pointer (see docs/protocol_specification.md).
//   write transaction: first data byte after the address loads the register pointer, later bytes write
//                      registers[pointer++]
//   read transaction : returns registers[pointer++]   (pointer persists across transactions)
// Events come from the synchronized SDA/SCL samples (START/STOP/SCL edges); the slave needs a system clock of
// roughly >= 8x the SCL frequency. Open drain: sda_oe/scl_oe = 1 pulls the line LOW.
// Clock stretching: if stretch_cycles != 0 the slave holds SCL low for that many system clocks after the 8th bit
// of a received byte (before the ACK) and before presenting each read byte.
// force_nack_data (test hook): NACK received data bytes (the address is still acknowledged).
module i2c_slave #(parameter logic [7:0] ID_VALUE = 8'hA5) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [6:0]  slave_addr,
    input  logic [15:0] stretch_cycles,
    input  logic        force_nack_data,
    input  logic        sda_in,
    input  logic        scl_in,
    output logic        sda_oe,
    output logic        scl_oe
);
    localparam logic [3:0] S_IDLE = 4'd0, S_ADDR = 4'd1, S_ADDR_ACK = 4'd2, S_WRITE = 4'd3,
                           S_WR_ACK = 4'd4, S_READ = 4'd5, S_RD_ACK = 4'd6, S_WAIT = 4'd7;

    // input synchronizers (idle = 1)
    logic [1:0] sda_sr, scl_sr;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin sda_sr <= 2'b11; scl_sr <= 2'b11; end
        else        begin sda_sr <= {sda_sr[0], sda_in}; scl_sr <= {scl_sr[0], scl_in}; end
    wire sda_s = sda_sr[1];
    wire scl_s = scl_sr[1];

    wire start_det, stop_det, scl_rise, scl_fall;
    i2c_start_stop_detector u_det (.clk(clk), .rst_n(rst_n), .sda_s(sda_s), .scl_s(scl_s),
                                   .start_det(start_det), .stop_det(stop_det),
                                   .scl_rise(scl_rise), .scl_fall(scl_fall));

    logic [3:0]  st, bcnt;
    logic [7:0]  rx, tx, ptr;
    logic        rw, first_byte, ack_seen, m_nack, nack_sent;
    logic [15:0] str_cnt;

    logic        rb_wr_en, rb_rd_strobe;
    logic [7:0]  rb_wr_addr, rb_wr_data, rb_strobe_addr;
    wire  [7:0]  rd_data;
    i2c_register_bank #(.ID_VALUE(ID_VALUE)) u_rb (
        .clk(clk), .rst_n(rst_n), .rd_addr(ptr), .rd_data(rd_data),
        .rd_strobe(rb_rd_strobe), .rd_strobe_addr(rb_strobe_addr),
        .wr_en(rb_wr_en), .wr_addr(rb_wr_addr), .wr_data(rb_wr_data));

    wire match, rw_dec;
    i2c_address_decoder u_dec (.rx_byte(rx), .slave_addr(slave_addr), .match(match), .rw(rw_dec));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; bcnt <= '0; rx <= '0; tx <= '0; ptr <= '0; rw <= 1'b0; first_byte <= 1'b0;
            ack_seen <= 1'b0; m_nack <= 1'b0; nack_sent <= 1'b0; str_cnt <= '0;
            sda_oe <= 1'b0; scl_oe <= 1'b0;
            rb_wr_en <= 1'b0; rb_rd_strobe <= 1'b0; rb_wr_addr <= '0; rb_wr_data <= '0; rb_strobe_addr <= '0;
        end else begin
            rb_wr_en <= 1'b0; rb_rd_strobe <= 1'b0;

            // stretch countdown (a new stretch below overrides this; it can only start when str_cnt == 0)
            if (str_cnt != 16'd0) begin
                str_cnt <= str_cnt - 16'd1;
                if (str_cnt == 16'd1) scl_oe <= 1'b0;
            end

            if (stop_det) begin
                st <= S_IDLE; sda_oe <= 1'b0; scl_oe <= 1'b0; str_cnt <= '0; bcnt <= '0; ack_seen <= 1'b0;
            end else if (start_det) begin
                st <= S_ADDR; sda_oe <= 1'b0; scl_oe <= 1'b0; str_cnt <= '0; bcnt <= '0; ack_seen <= 1'b0;
            end else begin
                case (st)
                S_IDLE: ;

                S_ADDR: begin
                    if (scl_rise && bcnt < 4'd8) begin rx <= {rx[6:0], sda_s}; bcnt <= bcnt + 4'd1; end
                    if (scl_fall && bcnt == 4'd8) begin
                        if (match) begin
                            rw <= rw_dec; sda_oe <= 1'b1; st <= S_ADDR_ACK; ack_seen <= 1'b0;
                            if (stretch_cycles != 16'd0) begin scl_oe <= 1'b1; str_cnt <= stretch_cycles; end
                        end else st <= S_WAIT;
                    end
                end

                S_ADDR_ACK: begin
                    if (scl_rise) ack_seen <= 1'b1;
                    if (scl_fall && ack_seen) begin
                        ack_seen <= 1'b0; bcnt <= '0;
                        if (rw) begin                                   // master reads: present first byte
                            st <= S_READ; tx <= rd_data; sda_oe <= ~rd_data[7];
                            ptr <= ptr + 8'd1; rb_rd_strobe <= 1'b1; rb_strobe_addr <= ptr;
                            if (stretch_cycles != 16'd0) begin scl_oe <= 1'b1; str_cnt <= stretch_cycles; end
                        end else begin
                            st <= S_WRITE; sda_oe <= 1'b0; first_byte <= 1'b1;
                        end
                    end
                end

                S_WRITE: begin
                    if (scl_rise && bcnt < 4'd8) begin rx <= {rx[6:0], sda_s}; bcnt <= bcnt + 4'd1; end
                    if (scl_fall && bcnt == 4'd8) begin
                        if (first_byte) ptr <= rx;
                        else begin
                            rb_wr_en <= 1'b1; rb_wr_addr <= ptr; rb_wr_data <= rx; ptr <= ptr + 8'd1;
                        end
                        first_byte <= 1'b0;
                        nack_sent <= force_nack_data; sda_oe <= ~force_nack_data;   // ACK = pull low
                        st <= S_WR_ACK; ack_seen <= 1'b0;
                        if (stretch_cycles != 16'd0) begin scl_oe <= 1'b1; str_cnt <= stretch_cycles; end
                    end
                end

                S_WR_ACK: begin
                    if (scl_rise) ack_seen <= 1'b1;
                    if (scl_fall && ack_seen) begin
                        sda_oe <= 1'b0; bcnt <= '0; ack_seen <= 1'b0;
                        st <= nack_sent ? S_WAIT : S_WRITE;
                    end
                end

                S_READ: begin
                    if (scl_rise && bcnt < 4'd8) bcnt <= bcnt + 4'd1;
                    if (scl_fall) begin
                        if (bcnt >= 4'd1 && bcnt < 4'd8) begin tx <= {tx[6:0], 1'b0}; sda_oe <= ~tx[6]; end
                        else if (bcnt == 4'd8) begin sda_oe <= 1'b0; st <= S_RD_ACK; ack_seen <= 1'b0; end
                    end
                end

                S_RD_ACK: begin
                    if (scl_rise) begin m_nack <= sda_s; ack_seen <= 1'b1; end
                    if (scl_fall && ack_seen) begin
                        ack_seen <= 1'b0; bcnt <= '0;
                        if (m_nack) st <= S_WAIT;
                        else begin
                            st <= S_READ; tx <= rd_data; sda_oe <= ~rd_data[7];
                            ptr <= ptr + 8'd1; rb_rd_strobe <= 1'b1; rb_strobe_addr <= ptr;
                            if (stretch_cycles != 16'd0) begin scl_oe <= 1'b1; str_cnt <= stretch_cycles; end
                        end
                    end
                end

                S_WAIT: ;
                default: st <= S_IDLE;
                endcase
            end
        end
    end
endmodule
