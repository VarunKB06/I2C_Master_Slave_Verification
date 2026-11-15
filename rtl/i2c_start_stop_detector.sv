// Detects START/STOP and SCL edges from already-synchronized samples (one-cycle pulses).
module i2c_start_stop_detector (
    input  logic clk,
    input  logic rst_n,
    input  logic sda_s,
    input  logic scl_s,
    output logic start_det,    // SDA falls while SCL high
    output logic stop_det,     // SDA rises while SCL high
    output logic scl_rise,
    output logic scl_fall
);
    logic sda_d, scl_d;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin sda_d <= 1'b1; scl_d <= 1'b1; end
        else        begin sda_d <= sda_s; scl_d <= scl_s; end

    assign start_det = scl_s & scl_d &  sda_d & ~sda_s;
    assign stop_det  = scl_s & scl_d & ~sda_d &  sda_s;
    assign scl_rise  = ~scl_d &  scl_s;
    assign scl_fall  =  scl_d & ~scl_s;
endmodule
