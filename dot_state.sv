// =============================================================================
// dot_state.sv — Dot Pixel RAM
// =============================================================================
// Stores and manages the state of all dot pixels on the 640x480 maze.
// Each of the 307,200 pixels has a 1-bit entry: 1 = dot present, 0 = eaten.
//
// Initialized from dots.hex at programming time — a binary image generated
// by a Python script from a Paint-drawn dot layout at 640x480 resolution.
// Each 1 in the file corresponds to a yellow dot pixel on screen.
//
// Three operations happen every clock cycle:
//
//   1. Display read (read_addr):
//      The VGA beam's current pixel address is checked each cycle.
//      dot_alive output tells the pattern_generator whether to render
//      a yellow dot at the current beam position.
//
//   2. Eat write (eat_addr):
//      pac_controller sweeps a 32x32 window of addresses around Pac-Man
//      every cycle via eat_addr. If eat is high, the pixel at eat_addr
//      is erased (written to 0) regardless of whether it was a dot.
//
//   3. Dot eaten detection (dot_eaten):
//      Before erasing, was_dot captures whether eat_addr held a live dot.
//      dot_eaten pulses high only when eat is active AND the pixel was
//      actually a dot — this prevents empty pixels in the eat window
//      from being counted toward the score.
//
// Memory is implemented in M9K BRAM blocks to avoid consuming logic cells.
// Note: dot RAM cannot be reinitialized on reset since $readmemb only
// executes at programming time — a full reprogram is required to restore dots.
// =============================================================================

module dot_state (
    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    input  logic        clk,       // 50MHz system clock
    input  logic        reset_n,   // Active-low reset (does not reinitialize RAM)

    // -------------------------------------------------------------------------
    // Display Read Port
    // Checked every cycle by pattern_generator to determine dot pixel color
    // -------------------------------------------------------------------------
    input  logic [18:0] read_addr, // Current VGA beam pixel address (vcount*640 + hcount)
    output logic        dot_alive, // 1 = dot still present at read_addr, 0 = eaten

    // -------------------------------------------------------------------------
    // Eat Write Port
    // pac_controller sweeps a 32x32 window each cycle via eat_addr
    // -------------------------------------------------------------------------
    input  logic        eat,       // High when Pac-Man is moving and scanning for dots
    input  logic [18:0] eat_addr,  // Current pixel address in Pac-Man's 32x32 eat window

    // -------------------------------------------------------------------------
    // Dot Eaten Output
    // Pulses high when a live dot pixel is erased — used by score_tracker
    // -------------------------------------------------------------------------
    output logic        dot_eaten  // High for one cycle when a dot pixel is consumed
);

    // -------------------------------------------------------------------------
    // Dot Pixel Memory
    // 307,200 x 1-bit entries covering the full 640x480 display
    // Stored in M9K BRAM blocks to avoid consuming logic array blocks
    // Initialized from dots.hex at programming time via $readmemb
    // WARNING: This RAM cannot be reinitialized on reset_n — only on reprogram
    // -------------------------------------------------------------------------
    (* ramstyle = "M9K" *) logic [0:0] mem [0:307199];
    initial $readmemb("dots.hex", mem);

    // -------------------------------------------------------------------------
    // Was-Dot Register
    // Captures whether eat_addr held a live dot BEFORE the erase write occurs.
    // Required because eat fires over all pixels in Pac-Man's bounding box,
    // including empty floor pixels — was_dot filters out non-dot erasures
    // so the score tracker only counts actual dot pixels consumed.
    // -------------------------------------------------------------------------
    logic was_dot;

    // -------------------------------------------------------------------------
    // Eat Write Port — Erase dot at eat_addr each cycle when eat is high
    // was_dot samples the current value before the write so dot_eaten
    // can correctly detect whether a real dot was just erased
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        was_dot <= mem[eat_addr]; // Sample dot state before potential erase
        if (eat)
            mem[eat_addr] <= 1'b0; // Erase dot pixel (write 0)
    end

    // -------------------------------------------------------------------------
    // Display Read Port — Check dot state at current VGA beam position
    // Output registered one cycle — pattern_generator accounts for this latency
    // -------------------------------------------------------------------------
    always_ff @(posedge clk)
        dot_alive <= mem[read_addr];

    // -------------------------------------------------------------------------
    // Dot Eaten Detection
    // Pulses high only when eat is active AND the erased pixel was a live dot.
    // Registered output ensures clean single-cycle pulse to score_tracker.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk)
        dot_eaten <= eat && was_dot;

endmodule
