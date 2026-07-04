module sprite_rom (
    input  logic        clk,
    input  logic [12:0] addr,
    output logic [23:0] pixel_out
);
    logic [23:0] mem [0:8191];
    initial $readmemh("pacman_anim.hex", mem);

    always_ff @(posedge clk)
        pixel_out <= mem[addr];
endmodule