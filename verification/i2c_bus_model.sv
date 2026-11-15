`timescale 1ps/1ps
// Open-drain bus with pull-ups (the testbench's "i2c_bus_if"; a module is used because Icarus Verilog does not
// support SystemVerilog interfaces). Every device only PULLS A LINE LOW (oe = 1) or releases it (high impedance);
// the tri1 nets provide the pull-up. f_* are fault injectors that hold a line low (stuck-low tests).
module i2c_bus_model (
    input  logic m_sda_oe, m_scl_oe,
    input  logic s_sda_oe, s_scl_oe,
    input  logic f_sda_low, f_scl_low,
    output wire  sda,
    output wire  scl
);
    tri1 sda_n;
    tri1 scl_n;
    assign sda_n = m_sda_oe  ? 1'b0 : 1'bz;
    assign sda_n = s_sda_oe  ? 1'b0 : 1'bz;
    assign sda_n = f_sda_low ? 1'b0 : 1'bz;
    assign scl_n = m_scl_oe  ? 1'b0 : 1'bz;
    assign scl_n = s_scl_oe  ? 1'b0 : 1'bz;
    assign scl_n = f_scl_low ? 1'b0 : 1'bz;
    assign sda = sda_n;
    assign scl = scl_n;
endmodule
