module image_rom (
    input  logic        clk,
    input  logic        clk50,
    input  logic [18:0] addr,
    output logic        pixel_out,
    input  logic [18:0] col_addr,
    output logic        col_pixel
);
    (* ramstyle = "M9K" *) logic mem [0:307199];
    initial $readmemb("image.hex", mem);
    always_ff @(posedge clk)
        pixel_out <= mem[addr];
    always_ff @(posedge clk50)
        col_pixel <= mem[col_addr];
endmodule