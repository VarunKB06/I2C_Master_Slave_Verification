// Counts system clocks while `active` (SCL held low after the master released it). limit = 0 disables.
module i2c_timeout_monitor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        active,
    input  logic [15:0] limit,
    output logic        timeout
);
    logic [15:0] cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)       cnt <= '0;
        else if (!active) cnt <= '0;
        else if (cnt != 16'hFFFF) cnt <= cnt + 16'd1;
    end
    assign timeout = (limit != 16'd0) && active && (cnt >= limit);
endmodule
