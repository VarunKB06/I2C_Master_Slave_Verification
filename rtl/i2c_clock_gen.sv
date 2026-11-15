// Quarter-period tick generator. One SCL period = 4 ticks (see docs/architecture.md).
// The counter FREEZES while `hold` is high (master released SCL but the line is still low = clock stretching /
// bus held low), so the master FSM cannot advance while the bus is held low.
// quarter = system clocks per quarter SCL period; values below 4 behave as 4.
module i2c_clock_gen (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        run,
    input  logic        hold,
    input  logic [15:0] quarter,
    output logic        tick
);
    logic [15:0] cnt;
    wire  [15:0] q = (quarter < 16'd4) ? 16'd4 : quarter;

    assign tick = run && !hold && (cnt == q - 16'd1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      cnt <= '0;
        else if (!run)   cnt <= '0;
        else if (!hold)  cnt <= tick ? 16'd0 : cnt + 16'd1;
    end
endmodule
