module i2c_address_decoder (
    input  logic [7:0] rx_byte,      // {addr[6:0], rw}
    input  logic [6:0] slave_addr,
    output logic       match,
    output logic       rw            // 1 = read
);
    assign match = (rx_byte[7:1] == slave_addr);
    assign rw    = rx_byte[0];
endmodule
