// I2C master, byte-command interface (like a "byte controller"). See docs/architecture.md for the FSM.
//   One command = [START|repeated START] + [write byte | read byte] + [STOP], any subset:
//     cmd_start : generate START (repeated START if the bus is already owned by this master)
//     cmd_write : send cmd_wdata, sample the slave ACK  -> slave_nack = 1 if NACKed
//     cmd_read  : receive a byte (rdata), answer ACK (cmd_nack=0) or NACK (cmd_nack=1)
//     cmd_stop  : generate STOP afterwards
//   The 7-bit address + R/W is issued by the caller as a write byte right after START.
// Open drain: sda_oe/scl_oe = 1 pulls the line LOW, 0 releases it. The master never drives a line high.
// Clock stretching: SCL is released and the master waits until the line is actually high.
// Single master only (no arbitration). `quarter` >= 4 system clocks.
module i2c_master (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] quarter,          // system clocks per quarter SCL period
    input  logic [15:0] timeout_limit,    // clocks of stretch before abort; 0 = disabled

    input  logic        cmd_valid,
    output logic        cmd_ready,
    input  logic        cmd_start, cmd_stop, cmd_write, cmd_read, cmd_nack,
    input  logic [7:0]  cmd_wdata,

    output logic        done,             // one-cycle pulse when the command has finished
    output logic [7:0]  rdata,
    output logic        slave_nack,
    output logic        timeout_err,
    output logic        illegal_cmd,
    output logic        busy,
    output logic        bus_active,       // this master is between START and STOP

    input  logic        sda_in,
    input  logic        scl_in,
    output logic        sda_oe,
    output logic        scl_oe
);
    localparam logic [2:0] S_IDLE = 3'd0, S_START = 3'd1, S_BIT = 3'd2, S_STOP = 3'd3, S_DONE = 3'd4;

    logic [2:0] state, ph;
    logic [3:0] bcnt;                      // 0..7 data bits, 8 = ACK bit
    logic [7:0] sh;
    logic       c_start, c_stop, c_write, c_read, c_nack, ack_rx;

    // input synchronizers (idle = 1)
    logic [1:0] sda_sr, scl_sr;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin sda_sr <= 2'b11; scl_sr <= 2'b11; end
        else        begin sda_sr <= {sda_sr[0], sda_in}; scl_sr <= {scl_sr[0], scl_in}; end
    wire sda_s = sda_sr[1];
    wire scl_s = scl_sr[1];

    wire run  = (state == S_START) || (state == S_BIT) || (state == S_STOP);
    wire hold = run && !scl_oe && !scl_s;          // released SCL is still low: stretched / held
    wire tick, timeout;

    i2c_clock_gen        u_cg (.clk(clk), .rst_n(rst_n), .run(run), .hold(hold), .quarter(quarter), .tick(tick));
    i2c_timeout_monitor  u_to (.clk(clk), .rst_n(rst_n), .active(hold), .limit(timeout_limit), .timeout(timeout));

    assign cmd_ready = (state == S_IDLE);
    assign busy      = (state != S_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; ph <= '0; bcnt <= '0; sh <= '0;
            sda_oe <= 1'b0; scl_oe <= 1'b0; bus_active <= 1'b0;
            done <= 1'b0; rdata <= '0; slave_nack <= 1'b0; timeout_err <= 1'b0; illegal_cmd <= 1'b0;
            c_start <= 1'b0; c_stop <= 1'b0; c_write <= 1'b0; c_read <= 1'b0; c_nack <= 1'b0; ack_rx <= 1'b0;
        end else begin
            done <= 1'b0;
            if (run && timeout) begin                       // stuck-low / over-long stretch: abort, release bus
                sda_oe <= 1'b0; scl_oe <= 1'b0; bus_active <= 1'b0;
                timeout_err <= 1'b1; state <= S_DONE; ph <= '0;
            end else begin
                case (state)
                S_IDLE: if (cmd_valid) begin
                    c_start <= cmd_start; c_stop <= cmd_stop; c_write <= cmd_write; c_read <= cmd_read;
                    c_nack <= cmd_nack; sh <= cmd_wdata;
                    slave_nack <= 1'b0; timeout_err <= 1'b0; illegal_cmd <= 1'b0; ph <= '0; bcnt <= '0;
                    if (cmd_write && cmd_read)                 begin illegal_cmd <= 1'b1; state <= S_DONE; end
                    else if (cmd_start)                        state <= S_START;
                    else if (cmd_write || cmd_read) begin
                        if (bus_active) state <= S_BIT; else begin illegal_cmd <= 1'b1; state <= S_DONE; end
                    end else if (cmd_stop) begin
                        if (bus_active) state <= S_STOP; else begin illegal_cmd <= 1'b1; state <= S_DONE; end
                    end else begin illegal_cmd <= 1'b1; state <= S_DONE; end
                end

                S_START: if (tick) begin
                    case (ph)
                    3'd0: begin sda_oe <= 1'b0; ph <= 3'd1; end                 // release SDA (SCL may still be low)
                    3'd1: begin scl_oe <= 1'b0; ph <= 3'd2; end                 // release SCL
                    3'd2: ph <= 3'd3;                                           // setup time
                    3'd3: begin sda_oe <= 1'b1; bus_active <= 1'b1; ph <= 3'd4; end  // START
                    3'd4: ph <= 3'd5;                                           // hold time
                    default: begin                                              // SCL low, start finished
                        scl_oe <= 1'b1; ph <= 3'd0; bcnt <= '0;
                        if (c_write || c_read) state <= S_BIT; else state <= S_DONE;
                    end
                    endcase
                end

                S_BIT: if (tick) begin
                    case (ph)
                    3'd0: begin                                                  // SCL low: set SDA
                        if (bcnt < 4'd8) sda_oe <= c_write ? ~sh[7] : 1'b0;
                        else             sda_oe <= c_read && !c_nack;            // master ACK = pull low
                        ph <= 3'd1;
                    end
                    3'd1: begin scl_oe <= 1'b0; ph <= 3'd2; end                  // release SCL (stretch wait)
                    3'd2: begin                                                  // SCL high: sample
                        if (bcnt < 4'd8) begin if (c_read) sh <= {sh[6:0], sda_s}; end
                        else             begin if (c_write) ack_rx <= sda_s; end
                        ph <= 3'd3;
                    end
                    default: begin                                               // pull SCL low
                        scl_oe <= 1'b1; ph <= 3'd0;
                        if (bcnt < 4'd8) begin
                            if (c_write) sh <= {sh[6:0], 1'b0};
                            bcnt <= bcnt + 4'd1;
                        end else begin
                            if (c_read) rdata <= sh;
                            slave_nack <= c_write & ack_rx;
                            bcnt <= '0;
                            state <= c_stop ? S_STOP : S_DONE;
                        end
                    end
                    endcase
                end

                S_STOP: if (tick) begin
                    case (ph)
                    3'd0: begin sda_oe <= 1'b1; ph <= 3'd1; end                  // SDA low while SCL low
                    3'd1: begin scl_oe <= 1'b0; ph <= 3'd2; end                  // release SCL
                    3'd2: ph <= 3'd3;
                    3'd3: begin sda_oe <= 1'b0; bus_active <= 1'b0; ph <= 3'd4; end  // STOP: SDA rises while SCL high
                    default: begin ph <= 3'd0; state <= S_DONE; end              // bus-free time
                    endcase
                end

                S_DONE: begin done <= 1'b1; state <= S_IDLE; end
                default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
