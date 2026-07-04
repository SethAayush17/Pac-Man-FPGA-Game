// =============================================================================
// image_rom.sv — Maze Image ROM
// =============================================================================
// Stores the maze as a 1-bit per pixel binary image at 640x480 resolution
// (307,200 total bits). Loaded once at programming time from image.hex.
//
// A value of 1 represents a wall pixel (rendered blue during gameplay).
// A value of 0 represents an open corridor (floor or dot location).
//
// Two independent read ports are provided:
//   - pixel_out: clocked on the 25MHz VGA pixel clock — used by the pattern
//     generator to determine wall/floor color at the current beam position
//   - col_pixel: clocked on the 50MHz system clock — used by pac_controller
//     to perform wall collision lookahead checks before each movement step
//
// The (* ramstyle = "M9K" *) attribute instructs Quartus to implement this
// memory using dedicated M9K BRAM blocks on the Cyclone V rather than logic
// cells, which would be insufficient for a 307,200-bit array.
// =============================================================================

module image_rom (
    input  logic        clk,        // 25MHz VGA pixel clock (display read port)
    input  logic        clk50,      // 50MHz system clock (collision read port)
    input  logic [18:0] addr,       // Pixel address for display (vcount*640 + hcount)
    output logic        pixel_out,  // Wall pixel value at addr (1 = wall, 0 = open)
    input  logic [18:0] col_addr,   // Lookahead address from pac_controller for collision
    output logic        col_pixel   // Wall pixel value at col_addr (1 = wall, 0 = open)
);

    // -------------------------------------------------------------------------
    // Maze Memory Array
    // 307,200 single-bit entries covering the full 640x480 display
    // Stored in M9K BRAM blocks to avoid consuming logic array blocks
    // Initialized from image.hex at programming time via $readmemb
    // -------------------------------------------------------------------------
    (* ramstyle = "M9K" *) logic mem [0:307199];
    initial $readmemb("image.hex", mem);

    // -------------------------------------------------------------------------
    // Display Read Port — 25MHz VGA clock
    // Output registered to match the one-cycle ROM latency expected by
    // the pattern generator's pipeline
    // -------------------------------------------------------------------------
    always_ff @(posedge clk)
        pixel_out <= mem[addr];

    // -------------------------------------------------------------------------
    // Collision Read Port — 50MHz system clock
    // Clocked faster than the display port so pac_controller can check
    // wall pixels at the lookahead position within the same movement step
    // -------------------------------------------------------------------------
    always_ff @(posedge clk50)
        col_pixel <= mem[col_addr];

endmodule
