// =============================================================================
// vga_controller.sv — VGA Timing Generator
// =============================================================================
// Generates VGA sync signals and pixel beam coordinates (hcount, vcount)
// for a 640x480 display at 60Hz using a 25MHz pixel clock.
//
// Full frame timing (800 total columns x 525 total rows):
//   Horizontal: 640 visible + 16 front porch + 96 sync + 48 back porch = 800
//   Vertical:   480 visible + 10 front porch +  2 sync + 33 back porch = 525
//
// hcount and vcount count through the full frame including blanking regions.
// Pixel rendering should only occur when blank_n is high (active display area).
// =============================================================================

module vga_controller(
    input  logic        vga_clock, // 25MHz pixel clock
    input  logic        reset_n,   // Active-low reset
    output logic        sync_n,    // Composite sync — tied low (not used)
    output logic        blank_n,   // High only during active display region (640x480)
    output logic        hsync_n,   // Horizontal sync pulse (active low)
    output logic        vsync_n,   // Vertical sync pulse (active low)
    output logic [9:0]  hcount,    // Current horizontal pixel position (0–799)
    output logic [9:0]  vcount     // Current vertical line position (0–524)
);

    // -------------------------------------------------------------------------
    // Horizontal Counter
    // Counts 0–799 across each full scanline (640 visible + 160 blanking)
    // Resets to 0 after reaching 799 to start the next line
    // -------------------------------------------------------------------------
    always_ff @(posedge vga_clock or negedge reset_n) begin
        if (!reset_n)
            hcount <= 10'd0;
        else if (hcount == 10'd799)
            hcount <= 10'd0;
        else
            hcount <= hcount + 10'd1;
    end

    // -------------------------------------------------------------------------
    // Vertical Counter
    // Counts 0–524 across each full frame (480 visible lines + 45 blanking)
    // Increments once per scanline (when hcount rolls over at 799)
    // Resets to 0 after reaching 524 to start the next frame
    // -------------------------------------------------------------------------
    always_ff @(posedge vga_clock or negedge reset_n) begin
        if (!reset_n)
            vcount <= 10'd0;
        else if (hcount == 10'd799) begin
            if (vcount == 10'd524)
                vcount <= 10'd0;
            else
                vcount <= vcount + 10'd1;
        end
    end

    // -------------------------------------------------------------------------
    // VGA Signal Assignments
    // -------------------------------------------------------------------------

    // Composite sync — not used in standard VGA, tied low
    assign sync_n  = 1'b0;

    // Blanking: high only when beam is within the 640x480 active display area
    // All rendering logic should gate on blank_n to avoid drawing in blanking regions
    assign blank_n = (hcount < 10'd640) && (vcount < 10'd480);

    // Horizontal sync pulse: active low during columns 656–751
    // Signals the monitor to reset the beam to the start of the next line
    assign hsync_n = ~(hcount >= 10'd656 && hcount <= 10'd751);

    // Vertical sync pulse: active low during lines 490–491
    // Signals the monitor that the full frame is complete and beam returns to top
    assign vsync_n = ~(vcount >= 10'd490 && vcount <= 10'd491);

endmodule
