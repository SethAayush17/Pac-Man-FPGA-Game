// =============================================================================
// pac_controller.sv — Pac-Man Movement and Dot Eating Controller
// =============================================================================
// Controls Pac-Man's pixel position, direction, wall collision detection,
// tunnel wrapping, and dot eating scan.
//
// Movement timing:
//   Pac-Man moves one pixel every 400,000 clock cycles (8ms at 50MHz),
//   giving a smooth movement speed across the 640x480 maze.
//
// Wall collision:
//   Before each movement step, three points along the leading edge of
//   Pac-Man's bounding box are checked against the maze ROM (col_pixel).
//   These checks are spread across the cycles between movement steps using
//   check_cnt. If any check returns a wall pixel, wall_hit is set and
//   Pac-Man does not move that step.
//
// Tunnel wrapping:
//   When Pac-Man reaches the left or right edge while in the tunnel
//   row (y between 200–279), his position wraps to the opposite side.
//
// Dot eating:
//   Every cycle, a 32x32 scan window centered on Pac-Man's position is
//   swept using eat_x_cnt and eat_y_cnt counters. The current scan address
//   (eat_addr) is sent to dot_state, which erases dot pixels and pulses
//   dot_eaten when a live dot is found.
// =============================================================================

module pac_controller(
    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    input  logic        clock,      // 50MHz system clock
    input  logic        reset_n,    // Active-low reset

    // -------------------------------------------------------------------------
    // Joystick Input (12-bit ADC values)
    // Left/right: joystick_lr < 400h = left, > C00h = right
    // Up/down:    joystick_ud < 400h = up,   > C00h = down
    // -------------------------------------------------------------------------
    input  logic [11:0] joystick_lr,
    input  logic [11:0] joystick_ud,

    // -------------------------------------------------------------------------
    // Pac-Man Position and Direction
    // -------------------------------------------------------------------------
    output logic [9:0]  pac_x,      // Pac-Man top-left pixel X position
    output logic [9:0]  pac_y,      // Pac-Man top-left pixel Y position
    output logic [1:0]  direction,  // Current movement direction

    // -------------------------------------------------------------------------
    // Wall Collision Interface (to/from image_rom col port)
    // -------------------------------------------------------------------------
    output logic [18:0] col_addr,   // Lookahead address to check for wall pixel
    input  logic        col_pixel,  // 1 = wall at col_addr

    // -------------------------------------------------------------------------
    // Dot Eating Interface (to dot_state)
    // -------------------------------------------------------------------------
    output logic        eat,        // High while Pac-Man is moving (scan active)
    output logic [18:0] eat_addr,   // Current address in 32x32 dot scan window

    // -------------------------------------------------------------------------
    // Additional Outputs
    // -------------------------------------------------------------------------
    output logic        moving_out, // High when Pac-Man is actively moving
    output logic [9:0]  pac_tile_x, // Pac-Man center position in tile coordinates
    output logic [9:0]  pac_tile_y  // Pac-Man center position in tile coordinates
);

    // -------------------------------------------------------------------------
    // Size and Position Constants
    // -------------------------------------------------------------------------
    localparam PAC_SIZE  = 10'd32;   // Pac-Man sprite size (32x32 pixels)
    localparam TILE_W    = 10'd23;   // Maze tile width in pixels
    localparam TILE_H    = 10'd16;   // Maze tile height in pixels
    localparam [9:0] START_X = 10'd305; // Pac-Man starting X position (center of maze)
    localparam [9:0] START_Y = 10'd212; // Pac-Man starting Y position (center of maze)

    // -------------------------------------------------------------------------
    // Tunnel Row Range
    // Pac-Man wraps left/right only when within this vertical range
    // -------------------------------------------------------------------------
    localparam TUNNEL_Y_MIN = 10'd200;
    localparam TUNNEL_Y_MAX = 10'd279;

    // -------------------------------------------------------------------------
    // Direction Encoding
    // -------------------------------------------------------------------------
    localparam DIR_LEFT  = 2'd0;
    localparam DIR_RIGHT = 2'd1;
    localparam DIR_UP    = 2'd2;
    localparam DIR_DOWN  = 2'd3;

    // -------------------------------------------------------------------------
    // Internal Signals
    // -------------------------------------------------------------------------
    logic [19:0] speed_cnt;     // Counts up to 400,000 to time each movement step
    logic        move_en;       // Pulses high every 400,000 cycles to trigger movement
    logic [1:0]  next_dir;      // Desired direction from joystick
    logic [31:0] col_addr_full; // Full 32-bit collision address before truncation
    logic        moving;        // Internal moving state flag
    logic [1:0]  check_cnt;     // Cycles through 3 collision check points (0, 1, 2)
    logic        wall_hit;      // High if any collision check found a wall this step
    logic        prev_wall_hit; // wall_hit from previous movement step
    logic [4:0]  eat_x_cnt;     // X offset within 32x32 dot scan window (0–31)
    logic [4:0]  eat_y_cnt;     // Y offset within 32x32 dot scan window (0–31)
    logic        in_tunnel;     // High when Pac-Man is in the tunnel row range

    // -------------------------------------------------------------------------
    // Continuous Assignments
    // -------------------------------------------------------------------------

    // Movement enable: fires once every 400,000 cycles (8ms at 50MHz)
    assign move_en    = (speed_cnt == 20'd400000);
    assign moving_out = moving;

    // Tile position: center of Pac-Man sprite divided by tile dimensions
    assign pac_tile_x = (pac_x + PAC_SIZE/2) / TILE_W;
    assign pac_tile_y = (pac_y + PAC_SIZE/2) / TILE_H;

    // Tunnel detection: true when Pac-Man's Y is within the horizontal tunnel row
    assign in_tunnel  = (pac_y >= TUNNEL_Y_MIN && pac_y <= TUNNEL_Y_MAX);

    // Dot eat scan address: sweeps a 32x32 window starting at Pac-Man's top-left
    assign eat_addr = 19'(pac_y + 19'(eat_y_cnt)) * 19'd640 +
                      19'(pac_x + 19'(eat_x_cnt));

    // Eat signal active whenever Pac-Man is moving
    assign eat = moving;

    // -------------------------------------------------------------------------
    // Joystick Direction Decoder
    // ADC range 0–FFF: values below 400h = negative axis, above C00h = positive
    // LR takes priority over UD when both axes are deflected
    // -------------------------------------------------------------------------
    always_comb begin
        if (joystick_lr < 12'h400)
            next_dir = DIR_LEFT;
        else if (joystick_lr > 12'hC00)
            next_dir = DIR_RIGHT;
        else if (joystick_ud < 12'h400)
            next_dir = DIR_UP;
        else if (joystick_ud > 12'hC00)
            next_dir = DIR_DOWN;
        else
            next_dir = direction; // No deflection — hold current direction
    end

    // -------------------------------------------------------------------------
    // Collision Lookahead Address Generator
    // Three points along the leading edge are checked using check_cnt (0, 1, 2):
    //   Point 0: near top corner of leading edge
    //   Point 1: center of leading edge
    //   Point 2: near bottom corner of leading edge
    // This prevents Pac-Man from clipping through wall corners
    // -------------------------------------------------------------------------
    always_comb begin
        case (direction)
            DIR_LEFT: begin
                case (check_cnt)
                    2'd0: col_addr_full = 32'(pac_y + 3)            * 32'd640 + 32'(pac_x) - 32'd1;
                    2'd1: col_addr_full = 32'(pac_y + PAC_SIZE/2)   * 32'd640 + 32'(pac_x) - 32'd1;
                    2'd2: col_addr_full = 32'(pac_y + PAC_SIZE - 3) * 32'd640 + 32'(pac_x) - 32'd1;
                    default: col_addr_full = 32'd0;
                endcase
            end
            DIR_RIGHT: begin
                case (check_cnt)
                    2'd0: col_addr_full = 32'(pac_y + 3)            * 32'd640 + 32'(pac_x) + 32'(PAC_SIZE);
                    2'd1: col_addr_full = 32'(pac_y + PAC_SIZE/2)   * 32'd640 + 32'(pac_x) + 32'(PAC_SIZE);
                    2'd2: col_addr_full = 32'(pac_y + PAC_SIZE - 3) * 32'd640 + 32'(pac_x) + 32'(PAC_SIZE);
                    default: col_addr_full = 32'd0;
                endcase
            end
            DIR_UP: begin
                case (check_cnt)
                    // Check top edge: left corner, center, right corner
                    2'd0: col_addr_full = 32'(pac_y) * 32'd640 + 32'(pac_x) + 32'd3;
                    2'd1: col_addr_full = 32'(pac_y) * 32'd640 + 32'(pac_x) + 32'(PAC_SIZE/2);
                    2'd2: col_addr_full = 32'(pac_y) * 32'd640 + 32'(pac_x) + 32'(PAC_SIZE) - 32'd3;
                    default: col_addr_full = 32'd0;
                endcase
            end
            DIR_DOWN: begin
                // Check bottom edge: one row below Pac-Man's bottom
                case (check_cnt)
                    2'd0: col_addr_full = (32'(pac_y) + 32'(PAC_SIZE)) * 32'd640 + 32'(pac_x) + 32'd3;
                    2'd1: col_addr_full = (32'(pac_y) + 32'(PAC_SIZE)) * 32'd640 + 32'(pac_x) + 32'(PAC_SIZE/2);
                    2'd2: col_addr_full = (32'(pac_y) + 32'(PAC_SIZE)) * 32'd640 + 32'(pac_x) + 32'(PAC_SIZE) - 32'd3;
                    default: col_addr_full = 32'd0;
                endcase
            end
            default: col_addr_full = 32'd0;
        endcase
    end

    // Truncate to 19-bit ROM address (640x480 = 307,200 max address fits in 19 bits)
    assign col_addr = col_addr_full[18:0];

    // -------------------------------------------------------------------------
    // Main Sequential Logic
    // Handles: movement timing, direction changes, wall collision response,
    // tunnel wrapping, and dot scan counter
    // -------------------------------------------------------------------------
    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            speed_cnt     <= 0;
            pac_x         <= START_X;
            pac_y         <= START_Y;
            direction     <= DIR_RIGHT;
            moving        <= 1'b0;
            check_cnt     <= 0;
            wall_hit      <= 0;
            prev_wall_hit <= 0;
            eat_x_cnt     <= 0;
            eat_y_cnt     <= 0;
        end else begin
            speed_cnt <= speed_cnt + 1;

            // -----------------------------------------------------------------
            // Dot Scan Counter — sweeps eat_addr through 32x32 window each cycle
            // Wraps eat_x_cnt 0–31, then increments eat_y_cnt 0–31
            // -----------------------------------------------------------------
            if (eat_x_cnt == 5'd31) begin
                eat_x_cnt <= 0;
                if (eat_y_cnt == 5'd31)
                    eat_y_cnt <= 0;
                else
                    eat_y_cnt <= eat_y_cnt + 1;
            end else begin
                eat_x_cnt <= eat_x_cnt + 1;
            end

            if (move_en) begin
                // -------------------------------------------------------------
                // Movement Step — fires every 400,000 cycles
                // -------------------------------------------------------------
                speed_cnt     <= 0;
                check_cnt     <= 0;
                prev_wall_hit <= wall_hit; // Latch wall result from previous step
                wall_hit      <= 0;        // Reset for new collision checks

                // Update direction immediately on joystick input
                if (next_dir != direction) begin
                    direction <= next_dir;
                    moving    <= 1'b1;
                end

                // Move one pixel in current direction if no wall was detected
                if (moving && !prev_wall_hit) begin
                    case (direction)
                        DIR_LEFT:  if (pac_x > 0)       pac_x <= pac_x - 10'd1;
                        DIR_RIGHT: if (pac_x < 10'd608) pac_x <= pac_x + 10'd1;
                        DIR_UP:    if (pac_y > 0)        pac_y <= pac_y - 10'd1;
                        DIR_DOWN:  if (pac_y < 10'd448) pac_y <= pac_y + 10'd1;
                    endcase
                end

                // -------------------------------------------------------------
                // Tunnel Wrapping
                // When Pac-Man exits the left or right edge within the tunnel
                // row, wrap his position to the opposite side of the screen
                // -------------------------------------------------------------
                if (moving && in_tunnel && direction == DIR_LEFT  && pac_x == 0)
                    pac_x <= 10'd608;
                if (moving && in_tunnel && direction == DIR_RIGHT && pac_x >= 10'd608)
                    pac_x <= 10'd0;

            end else begin
                // -------------------------------------------------------------
                // Collision Check Phase — between movement steps
                // check_cnt cycles through 3 leading-edge sample points
                // col_pixel is the maze ROM result for col_addr from last cycle
                // wall_hit accumulates across all 3 checks (OR reduction)
                // -------------------------------------------------------------
                check_cnt <= check_cnt + 1;
                if (check_cnt == 2'd0)
                    wall_hit <= col_pixel;          // First check — initialize
                else
                    wall_hit <= wall_hit | col_pixel; // Subsequent checks — accumulate
            end
        end
    end

endmodule
