// =============================================================================
// score_tracker.sv — Dot Pixel Score Counter
// =============================================================================
// Counts the total number of dot pixels eaten by Pac-Man during gameplay.
// Increments by 1 each time dot_state pulses dot_eaten high, which occurs
// once per eaten dot pixel.
//
// Since dots are stored as individual pixels rather than tiles, the win
// condition is reached at 14,256 — the total number of dot pixels in the
// maze image rather than the number of discrete dots.
//
// The score is read by display.sv every cycle to check the win condition
// (score == 14,256 AND Pac-Man returned to center) and by the pattern
// generator to drive the seven-segment displays.
//
// Score resets to 0 on reset_n but the dot RAM itself does not reinitialize
// on reset — a full reprogram is required to restore eaten dots.
// =============================================================================

module score_tracker (
    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    input  logic        clock,     // 50MHz system clock
    input  logic        reset_n,   // Active-low reset — clears score to 0

    // -------------------------------------------------------------------------
    // Input
    // -------------------------------------------------------------------------
    input  logic        dot_eaten, // Single-cycle pulse from dot_state when a dot pixel is erased

    // -------------------------------------------------------------------------
    // Output
    // -------------------------------------------------------------------------
    output logic [15:0] score      // Running total of dot pixels eaten (max 14,256)
);

    // -------------------------------------------------------------------------
    // Score Counter
    // Increments on every dot_eaten pulse
    // Win condition checked externally in display.sv at score == 14,256
    // -------------------------------------------------------------------------
    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n)
            score <= 0;           // Clear score on reset
        else if (dot_eaten)
            score <= score + 1;   // Increment once per eaten dot pixel
    end

endmodule
