// =============================================================================
// ghost_controller.sv — Replay Buffer Ghost Controller
// =============================================================================
// Implements a ghost that follows Pac-Man's exact path with a fixed time delay
// by recording Pac-Man's position and direction history into a circular buffer
// and replaying it DELAY samples later.
//
// How it works:
//   Every SAMPLE_RATE clock cycles (120,000 = 2.4ms at 50MHz), the current
//   Pac-Man position and direction are written into a circular history buffer
//   at write_ptr. Simultaneously, the ghost reads from read_ptr, which is
//   always DELAY samples behind write_ptr. This produces a ghost that traces
//   Pac-Man's exact path but arrives at each position ~1.2 seconds later.
//
// Buffer details:
//   BUFFER_SIZE = 512 entries (circular, indexed by 9-bit pointer)
//   DELAY       = 511 samples = 511 x 2.4ms ≈ 1.2 second lag
//   Each entry stores: pac_x (10-bit), pac_y (10-bit), pac_dir (2-bit)
//
// Startup behavior:
//   The ghost stays off-screen (700, 700) until the buffer has accumulated
//   at least DELAY samples. This prevents the ghost from snapping to an
//   incorrect position during the first DELAY samples of gameplay.
//   Buffer is pre-initialized to Pac-Man's start position so the ghost
//   smoothly enters from center when it first becomes ready.
//
// Off-screen convention:
//   ghost_x/ghost_y = 700 signals to pattern_generator that the ghost
//   should not be rendered (700 is outside the 640x480 active display area).
// =============================================================================

module ghost_controller(
    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    input  logic        clock,       // 50MHz system clock
    input  logic        reset_n,     // Active-low reset

    // -------------------------------------------------------------------------
    // Game State
    // -------------------------------------------------------------------------
    input  logic        game_active, // High during gameplay — ghost only moves when active

    // -------------------------------------------------------------------------
    // Pac-Man Position and Direction (sampled into history buffer)
    // -------------------------------------------------------------------------
    input  logic [9:0]  pac_x,      // Pac-Man X pixel position
    input  logic [9:0]  pac_y,      // Pac-Man Y pixel position
    input  logic [1:0]  pac_dir,    // Pac-Man movement direction

    // -------------------------------------------------------------------------
    // Ghost Position and Direction Output (replayed from history buffer)
    // -------------------------------------------------------------------------
    output logic [9:0]  ghost_x,    // Ghost X pixel position (700 = off-screen/hidden)
    output logic [9:0]  ghost_y,    // Ghost Y pixel position (700 = off-screen/hidden)
    output logic [1:0]  ghost_dir   // Ghost movement direction
);

    // -------------------------------------------------------------------------
    // Buffer Parameters
    // -------------------------------------------------------------------------
    localparam BUFFER_SIZE = 512;          // Circular buffer depth (must be power of 2)
    localparam DELAY       = 9'd511;       // Number of samples ghost lags behind Pac-Man
    localparam SAMPLE_RATE = 20'd120000;   // Cycles between samples (2.4ms at 50MHz)

    // -------------------------------------------------------------------------
    // History Buffer Arrays
    // One entry per sample — stores Pac-Man's complete state at each sample point
    // Implemented as registers (not BRAM) since they are accessed by computed index
    // -------------------------------------------------------------------------
    logic [9:0]  history_x   [0:BUFFER_SIZE-1]; // Pac-Man X history
    logic [9:0]  history_y   [0:BUFFER_SIZE-1]; // Pac-Man Y history
    logic [1:0]  history_dir [0:BUFFER_SIZE-1]; // Pac-Man direction history

    // -------------------------------------------------------------------------
    // Circular Buffer Pointers and Counters
    // -------------------------------------------------------------------------
    logic [8:0]  write_ptr;     // Points to next write slot in circular buffer
    logic [8:0]  read_ptr;      // Points to sample DELAY steps behind write_ptr
    logic [19:0] sample_cnt;    // Counts clock cycles between samples
    logic        sample_en;     // Pulses high every SAMPLE_RATE cycles
    logic [8:0]  buffer_filled; // Tracks how many samples have been written so far
    logic        ready;         // High once buffer has accumulated at least DELAY samples

    // -------------------------------------------------------------------------
    // Control Signal Assignments
    // -------------------------------------------------------------------------
    assign sample_en = (sample_cnt == SAMPLE_RATE);
    assign ready     = (buffer_filled >= DELAY);

    // -------------------------------------------------------------------------
    // Buffer Pre-initialization
    // All entries initialized to Pac-Man's start position so the ghost
    // enters from the correct location when ready flag first goes high
    // -------------------------------------------------------------------------
    integer i;
    initial begin
        for (i = 0; i < BUFFER_SIZE; i = i + 1) begin
            history_x[i]   = 10'd314; // Pac-Man start X
            history_y[i]   = 10'd208; // Pac-Man start Y
            history_dir[i] = 2'd1;    // Initial direction: right
        end
    end

    // -------------------------------------------------------------------------
    // Circular Buffer State Machine
    // On each sample_en pulse:
    //   1. Write current Pac-Man state to write_ptr
    //   2. Advance write_ptr (wraps automatically via 9-bit overflow)
    //   3. Increment buffer_filled until it saturates at 511
    //   4. If ready: set read_ptr = write_ptr - DELAY and output history
    //   5. If not ready: hold ghost off-screen at (700, 700)
    // -------------------------------------------------------------------------
    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            write_ptr     <= 0;
            read_ptr      <= 0;
            sample_cnt    <= 0;
            buffer_filled <= 0;
            ghost_x       <= 10'd700; // Off-screen on reset
            ghost_y       <= 10'd700;
            ghost_dir     <= 2'd1;
        end else begin
            if (game_active) begin
                sample_cnt <= sample_cnt + 1;

                if (sample_en) begin
                    sample_cnt <= 0;

                    // Write current Pac-Man state into circular buffer
                    history_x[write_ptr]   <= pac_x;
                    history_y[write_ptr]   <= pac_y;
                    history_dir[write_ptr] <= pac_dir;
                    write_ptr              <= write_ptr + 1; // Wraps at 512 via 9-bit overflow

                    // Track how many samples have been accumulated (cap at 511)
                    if (buffer_filled < 9'd511)
                        buffer_filled <= buffer_filled + 1;

                    if (ready) begin
                        // Buffer has enough history — read from DELAY samples ago
                        read_ptr  <= write_ptr - DELAY;
                        ghost_x   <= history_x[read_ptr];
                        ghost_y   <= history_y[read_ptr];
                        ghost_dir <= history_dir[read_ptr];
                    end else begin
                        // Not enough history yet — keep ghost hidden off-screen
                        ghost_x   <= 10'd700;
                        ghost_y   <= 10'd700;
                        ghost_dir <= 2'd1;
                    end
                end
            end
        end
    end

endmodule
