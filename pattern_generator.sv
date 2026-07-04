// =============================================================================
// pattern_generator.sv — Pixel Color Output / Rendering Engine
// =============================================================================
// Computes the RGB color of every pixel on every clock cycle as the VGA beam
// scans across the screen. There is no frame buffer — all rendering is done
// in real time using the current beam position (hcount, vcount).
//
// Rendering priority (highest to lowest):
//   1. Pac-Man sprite (non-magenta pixels only)
//   2. Ghost 1 sprite
//   3. Ghost 2 (red/replay ghost) sprite
//   4. Ghost 3 sprite
//   5. Ghost 4 sprite
//   6. Portal sprite
//   7. Maze wall (blue), dot (yellow), or open floor (white)
//
// All sprites use magenta (FF00FF) as a transparency key — magenta pixels
// are skipped so the background shows through.
//
// Title, lose, and win screens are rendered as white-on-black 1-bit images
// centered in the 640x480 display area (320x240 region at offset 160,120).
//
// Ghost positions are registered one cycle to match ROM read latency.
// All visibility and pixel signals are pipelined through _r/_rr registers
// to stay aligned with the two-cycle ROM read delay.
// =============================================================================

module pattern_generator(
    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    input  logic        vga_clock,  // 25MHz pixel clock
    input  logic        reset_n,    // Active-low reset

    // -------------------------------------------------------------------------
    // VGA Beam Position
    // -------------------------------------------------------------------------
    input  logic [9:0]  hcount,     // Current horizontal pixel (0–799)
    input  logic [9:0]  vcount,     // Current vertical line (0–524)

    // -------------------------------------------------------------------------
    // Sprite Positions and Directions
    // -------------------------------------------------------------------------
    input  logic [9:0]  pac_x,    pac_y,    // Pac-Man pixel position
    input  logic [9:0]  ghost_x,  ghost_y,  // Ghost 1 position (waypoint follower)
    input  logic [9:0]  rghost_x, rghost_y, // Ghost 2 position (replay buffer ghost)
    input  logic [9:0]  ghost3_x, ghost3_y, // Ghost 3 position (waypoint follower)
    input  logic [9:0]  ghost4_x, ghost4_y, // Ghost 4 position (waypoint follower)
    input  logic [1:0]  direction,           // Pac-Man movement direction
    input  logic [1:0]  ghost_dir,           // Ghost 1 direction
    input  logic [1:0]  ghost2_dir,          // Ghost 2 direction
    input  logic [1:0]  ghost3_dir,          // Ghost 3 direction
    input  logic [1:0]  ghost4_dir,          // Ghost 4 direction

    // -------------------------------------------------------------------------
    // Maze and Dot Data (from image_rom and dot_state)
    // -------------------------------------------------------------------------
    input  logic        pixel_data, // 1 = wall pixel at current vga_addr
    input  logic        dot_alive,  // 1 = uneaten dot at current vga_addr

    // -------------------------------------------------------------------------
    // Game State Flags
    // -------------------------------------------------------------------------
    input  logic        game_over,
    input  logic        win,
    input  logic        title_active,
    input  logic [1:0]  game_state,

    // -------------------------------------------------------------------------
    // Screen Image Pixels (from title_rom, lose_rom, win_rom)
    // -------------------------------------------------------------------------
    input  logic        title_pixel, // 1 = white pixel in title screen image
    input  logic        lose_pixel,  // 1 = white pixel in lose screen image
    input  logic        win_pixel,   // 1 = white pixel in win screen image

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    output logic [18:0] vga_addr,   // ROM address for current pixel (vcount*640 + hcount)
    output logic [7:0]  red,        // VGA red channel output
    output logic [7:0]  green,      // VGA green channel output
    output logic [7:0]  blue        // VGA blue channel output
);

    // -------------------------------------------------------------------------
    // Display and Sprite Size Constants
    // -------------------------------------------------------------------------
    localparam IMG_W      = 10'd640;  // Active display width
    localparam IMG_H      = 10'd480;  // Active display height
    localparam PAC_SIZE   = 10'd32;   // Pac-Man sprite size (32x32 pixels)
    localparam GHOST_SIZE = 10'd32;   // Ghost sprite size (32x32 pixels)

    // -------------------------------------------------------------------------
    // Direction Encoding
    // -------------------------------------------------------------------------
    localparam DIR_LEFT  = 2'd0;
    localparam DIR_RIGHT = 2'd1;
    localparam DIR_UP    = 2'd2;
    localparam DIR_DOWN  = 2'd3;

    // -------------------------------------------------------------------------
    // Portal Position and Size
    // -------------------------------------------------------------------------
    localparam PORTAL_X    = 10'd288;
    localparam PORTAL_Y    = 10'd204;
    localparam PORTAL_SIZE = 10'd64;  // Portal sprite is 64x64 pixels

    // -------------------------------------------------------------------------
    // Title/Win/Lose Screen Region (320x240 centered in 640x480)
    // -------------------------------------------------------------------------
    localparam TITLE_X0 = 10'd160;
    localparam TITLE_X1 = 10'd480;
    localparam TITLE_Y0 = 10'd120;
    localparam TITLE_Y1 = 10'd360;

    // -------------------------------------------------------------------------
    // Game State Encoding (matches display.sv)
    // -------------------------------------------------------------------------
    localparam S_TITLE   = 2'd0;
    localparam S_PLAYING = 2'd1;
    localparam S_LOSE    = 2'd2;
    localparam S_WIN     = 2'd3;

    // -------------------------------------------------------------------------
    // Pipeline Registers
    // All visibility/pixel signals registered to align with 2-cycle ROM latency
    // -------------------------------------------------------------------------
    logic        in_image, in_image_r;
    logic        pixel_data_r, dot_alive_r;
    logic        game_over_r, win_r, title_active_r;
    logic [1:0]  game_state_r;
    logic        title_pixel_r, lose_pixel_r, win_pixel_r;
    logic        in_title, in_title_r, in_title_rr; // Double-registered for 2-cycle ROM delay

    // -------------------------------------------------------------------------
    // Sprite Visibility Flags (registered one cycle for ROM alignment)
    // -------------------------------------------------------------------------
    logic        pac_visible,    pac_visible_r;
    logic        ghost_visible,  ghost_visible_r;
    logic        rghost_visible, rghost_visible_r;
    logic        ghost3_visible, ghost3_visible_r;
    logic        ghost4_visible, ghost4_visible_r;
    logic        portal_visible, portal_visible_r;

    // -------------------------------------------------------------------------
    // Sprite ROM Addresses and Pixel Outputs
    // -------------------------------------------------------------------------
    logic [12:0] sprite_addr;         // Pac-Man sprite address (8 frames x 32x32)
    logic [11:0] ghost_sprite_addr;   // Ghost 1 sprite address (4 dirs x 32x32)
    logic [11:0] rghost_sprite_addr;  // Ghost 2 sprite address
    logic [11:0] ghost3_sprite_addr;  // Ghost 3 sprite address
    logic [11:0] ghost4_sprite_addr;  // Ghost 4 sprite address
    logic [11:0] portal_sprite_addr;  // Portal sprite address (64x64)
    logic [23:0] sprite_pixel;        // 24-bit RGB pixel from Pac-Man ROM
    logic [23:0] ghost_pixel;         // 24-bit RGB pixel from ghost 1 ROM
    logic [23:0] rghost_pixel;        // 24-bit RGB pixel from ghost 2 ROM
    logic [23:0] ghost3_pixel;        // 24-bit RGB pixel from ghost 3 ROM
    logic [23:0] ghost4_pixel;        // 24-bit RGB pixel from ghost 4 ROM
    logic [23:0] portal_pixel;        // 24-bit RGB pixel from portal ROM

    // -------------------------------------------------------------------------
    // Transparency Flags
    // A sprite pixel is transparent if it is magenta (FF00FF) or near-white
    // Near-white check catches anti-aliased edge pixels around the background
    // -------------------------------------------------------------------------
    logic        ghost_transparent;
    logic        rghost_transparent;
    logic        ghost3_transparent;
    logic        ghost4_transparent;
    logic        portal_transparent;

    // -------------------------------------------------------------------------
    // Animation State
    // Pac-Man sprite alternates between two frames (open/closed mouth)
    // at ~8Hz using a 22-bit counter toggling at 3,000,000 cycles (~120ms at 25MHz)
    // -------------------------------------------------------------------------
    logic [21:0] anim_cnt;
    logic        frame;      // 0 or 1 — selects open/closed mouth frame
    logic [2:0]  anim_frame; // {direction[1:0], frame} — selects row in sprite sheet

    // -------------------------------------------------------------------------
    // Ghost Position Pipeline Registers
    // Ghost positions registered one cycle to align with ROM read latency
    // -------------------------------------------------------------------------
    logic [9:0]  ghost_x_r,  ghost_y_r;
    logic [9:0]  rghost_x_r, rghost_y_r;
    logic [9:0]  ghost3_x_r, ghost3_y_r;
    logic [9:0]  ghost4_x_r, ghost4_y_r;
    logic [1:0]  ghost_dir_r, ghost2_dir_r, ghost3_dir_r, ghost4_dir_r;

    // -------------------------------------------------------------------------
    // Register Ghost Positions and Directions
    // Delayed one cycle to match ROM read latency for correct sprite alignment
    // -------------------------------------------------------------------------
    always_ff @(posedge vga_clock) begin
        ghost_x_r  <= ghost_x;  ghost_y_r  <= ghost_y;
        rghost_x_r <= rghost_x; rghost_y_r <= rghost_y;
        ghost3_x_r <= ghost3_x; ghost3_y_r <= ghost3_y;
        ghost4_x_r <= ghost4_x; ghost4_y_r <= ghost4_y;
        ghost_dir_r  <= ghost_dir;
        ghost2_dir_r <= ghost2_dir;
        ghost3_dir_r <= ghost3_dir;
        ghost4_dir_r <= ghost4_dir;
    end

    // -------------------------------------------------------------------------
    // Active Region and ROM Address
    // -------------------------------------------------------------------------
    assign in_image  = (hcount < IMG_W && vcount < IMG_H);
    assign vga_addr  = 19'(vcount) * 19'd640 + 19'(hcount); // Linear pixel address
    assign in_title  = (hcount >= TITLE_X0 && hcount < TITLE_X1 &&
                        vcount >= TITLE_Y0  && vcount < TITLE_Y1);

    // -------------------------------------------------------------------------
    // Sprite Visibility — True when beam is within the sprite bounding box
    // -------------------------------------------------------------------------
    assign pac_visible    = (hcount >= pac_x      && hcount < pac_x      + PAC_SIZE    && vcount >= pac_y      && vcount < pac_y      + PAC_SIZE);
    assign ghost_visible  = (hcount >= ghost_x_r  && hcount < ghost_x_r  + GHOST_SIZE  && vcount >= ghost_y_r  && vcount < ghost_y_r  + GHOST_SIZE);
    assign rghost_visible = (hcount >= rghost_x_r && hcount < rghost_x_r + GHOST_SIZE  && vcount >= rghost_y_r && vcount < rghost_y_r + GHOST_SIZE);
    assign ghost3_visible = (hcount >= ghost3_x_r && hcount < ghost3_x_r + GHOST_SIZE  && vcount >= ghost3_y_r && vcount < ghost3_y_r + GHOST_SIZE);
    assign ghost4_visible = (hcount >= ghost4_x_r && hcount < ghost4_x_r + GHOST_SIZE  && vcount >= ghost4_y_r && vcount < ghost4_y_r + GHOST_SIZE);
    assign portal_visible = (hcount >= PORTAL_X   && hcount < PORTAL_X   + PORTAL_SIZE && vcount >= PORTAL_Y   && vcount < PORTAL_Y   + PORTAL_SIZE);

    // -------------------------------------------------------------------------
    // Transparency Detection
    // Magenta (FF00FF) is the background color in all sprite sheets
    // Near-white check (all channels > E0) catches anti-aliased background edges
    // -------------------------------------------------------------------------
    assign ghost_transparent  = (ghost_pixel  == 24'hFF00FF) || (ghost_pixel[23:16]  > 8'hE0 && ghost_pixel[15:8]  > 8'hE0 && ghost_pixel[7:0]  > 8'hE0);
    assign rghost_transparent = (rghost_pixel == 24'hFF00FF) || (rghost_pixel[23:16] > 8'hE0 && rghost_pixel[15:8] > 8'hE0 && rghost_pixel[7:0] > 8'hE0);
    assign ghost3_transparent = (ghost3_pixel == 24'hFF00FF) || (ghost3_pixel[23:16] > 8'hE0 && ghost3_pixel[15:8] > 8'hE0 && ghost3_pixel[7:0] > 8'hE0);
    assign ghost4_transparent = (ghost4_pixel == 24'hFF00FF) || (ghost4_pixel[23:16] > 8'hE0 && ghost4_pixel[15:8] > 8'hE0 && ghost4_pixel[7:0] > 8'hE0);
    assign portal_transparent = (portal_pixel == 24'hFF00FF) || (portal_pixel[23:16] > 8'hE0 && portal_pixel[15:8] > 8'hE0 && portal_pixel[7:0] > 8'hE0);

    // -------------------------------------------------------------------------
    // Pac-Man Animation Frame Selection
    // Sprite sheet rows: 0=right, 1=left, 2=up, 3=down (each with 2 frames)
    // anim_frame = {direction[1:0], frame_bit} selects row and open/closed mouth
    // -------------------------------------------------------------------------
    always_comb begin
        case (direction)
            DIR_RIGHT: anim_frame = {2'd0, frame};
            DIR_LEFT:  anim_frame = {2'd1, frame};
            DIR_UP:    anim_frame = {2'd2, frame};
            DIR_DOWN:  anim_frame = {2'd3, frame};
            default:   anim_frame = {2'd0, frame};
        endcase
    end

    // -------------------------------------------------------------------------
    // Sprite ROM Address Computation
    // Each sprite sheet row is 1024 pixels (32x32), direction selects the row
    // Pixel within the row = (vcount - sprite_y) * 32 + (hcount - sprite_x)
    // -------------------------------------------------------------------------
    assign sprite_addr        = 13'(anim_frame)   * 13'd1024 + 13'(vcount - pac_y)      * 13'd32 + 13'(hcount - pac_x);
    assign ghost_sprite_addr  = 12'(ghost_dir_r)  * 12'd1024 + 12'(vcount - ghost_y_r)  * 12'd32 + 12'(hcount - ghost_x_r);
    assign rghost_sprite_addr = 12'(ghost2_dir_r) * 12'd1024 + 12'(vcount - rghost_y_r) * 12'd32 + 12'(hcount - rghost_x_r);
    assign ghost3_sprite_addr = 12'(ghost3_dir_r) * 12'd1024 + 12'(vcount - ghost3_y_r) * 12'd32 + 12'(hcount - ghost3_x_r);
    assign ghost4_sprite_addr = 12'(ghost4_dir_r) * 12'd1024 + 12'(vcount - ghost4_y_r) * 12'd32 + 12'(hcount - ghost4_x_r);
    assign portal_sprite_addr = 12'(vcount - PORTAL_Y) * 12'd64 + 12'(hcount - PORTAL_X);

    // -------------------------------------------------------------------------
    // Animation Counter
    // Toggles frame bit every 3,000,000 pixel clock cycles (~120ms at 25MHz)
    // producing ~8Hz mouth open/close animation
    // -------------------------------------------------------------------------
    always_ff @(posedge vga_clock or negedge reset_n) begin
        if (!reset_n) begin
            anim_cnt <= 0;
            frame    <= 0;
        end else begin
            anim_cnt <= anim_cnt + 1;
            if (anim_cnt == 22'd3000000) begin
                anim_cnt <= 0;
                frame    <= ~frame;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline Stage — Register All Visibility and Pixel Signals
    // Aligns all signals with the 1-cycle ROM read latency
    // in_title is double-registered (in_title_rr) for the 2-cycle screen ROM delay
    // -------------------------------------------------------------------------
    always_ff @(posedge vga_clock) begin
        in_image_r       <= in_image;
        in_title_r       <= in_title;
        in_title_rr      <= in_title_r;     // Second pipeline stage for screen ROMs
        pixel_data_r     <= pixel_data;
        dot_alive_r      <= dot_alive;
        pac_visible_r    <= pac_visible;
        ghost_visible_r  <= ghost_visible;
        rghost_visible_r <= rghost_visible;
        ghost3_visible_r <= ghost3_visible;
        ghost4_visible_r <= ghost4_visible;
        portal_visible_r <= portal_visible;
        game_over_r      <= game_over;
        win_r            <= win;
        title_active_r   <= title_active;
        title_pixel_r    <= title_pixel;
        lose_pixel_r     <= lose_pixel;
        win_pixel_r      <= win_pixel;
        game_state_r     <= game_state;
    end

    // -------------------------------------------------------------------------
    // Sprite ROM Instantiations
    // Each ROM is synchronous — pixel output available one cycle after address
    // -------------------------------------------------------------------------
    sprite_rom  sprite_inst        (.clk(vga_clock), .addr(sprite_addr),        .pixel_out(sprite_pixel)); // Pac-Man (24-bit RGB, 8 frames)
    ghost_rom   ghost_sprite_inst  (.clk(vga_clock), .addr(ghost_sprite_addr),  .pixel_out(ghost_pixel));  // Ghost 1
    ghost2_rom  ghost2_sprite_inst (.clk(vga_clock), .addr(rghost_sprite_addr), .pixel_out(rghost_pixel)); // Ghost 2 (red/replay)
    ghost3_rom  ghost3_sprite_inst (.clk(vga_clock), .addr(ghost3_sprite_addr), .pixel_out(ghost3_pixel)); // Ghost 3
    ghost4_rom  ghost4_sprite_inst (.clk(vga_clock), .addr(ghost4_sprite_addr), .pixel_out(ghost4_pixel)); // Ghost 4
    portal_rom  portal_inst        (.clk(vga_clock), .addr(portal_sprite_addr), .pixel_out(portal_pixel)); // Portal (64x64)

    // -------------------------------------------------------------------------
    // Pixel Color Output — Rendering Priority Chain
    // Evaluated combinationally every pixel clock cycle
    //
    // Title/Lose/Win screens: white pixel = FF,FF,FF; background = 00,00,00
    // Gameplay priority:
    //   Pac-Man > Ghost1 > Ghost2 > Ghost3 > Ghost4 > Portal > Maze/Dot/Floor
    //   Wall    = blue  (00, 00, FF)
    //   Dot     = yellow(FF, FF, 00)
    //   Floor   = white (FF, FF, FF)
    // -------------------------------------------------------------------------
    always_comb begin
        case (game_state_r)

            // Title screen: render 320x240 title image centered on black background
            S_TITLE: begin
                if (in_title_rr && title_pixel_r)
                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end
                else
                    begin red = 8'h00; green = 8'h00; blue = 8'h00; end
            end

            // Lose screen: render 320x240 lose image centered on black background
            S_LOSE: begin
                if (in_title_rr && lose_pixel_r)
                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end
                else
                    begin red = 8'h00; green = 8'h00; blue = 8'h00; end
            end

            // Win screen: render 320x240 win image centered on black background
            S_WIN: begin
                if (in_title_rr && win_pixel_r)
                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end
                else
                    begin red = 8'h00; green = 8'h00; blue = 8'h00; end
            end

            // Gameplay: layered sprite and maze rendering
            S_PLAYING: begin
                if (pac_visible_r && sprite_pixel != 24'hFF00FF)
                    // Pac-Man sprite — skip magenta (transparent) pixels
                    begin red = sprite_pixel[23:16]; green = sprite_pixel[15:8]; blue = sprite_pixel[7:0]; end
                else if (ghost_visible_r && !ghost_transparent)
                    // Ghost 1
                    begin red = ghost_pixel[23:16]; green = ghost_pixel[15:8]; blue = ghost_pixel[7:0]; end
                else if (rghost_visible_r && !rghost_transparent)
                    // Ghost 2 (red/replay)
                    begin red = rghost_pixel[23:16]; green = rghost_pixel[15:8]; blue = rghost_pixel[7:0]; end
                else if (ghost3_visible_r && !ghost3_transparent)
                    // Ghost 3
                    begin red = ghost3_pixel[23:16]; green = ghost3_pixel[15:8]; blue = ghost3_pixel[7:0]; end
                else if (ghost4_visible_r && !ghost4_transparent)
                    // Ghost 4
                    begin red = ghost4_pixel[23:16]; green = ghost4_pixel[15:8]; blue = ghost4_pixel[7:0]; end
                else if (portal_visible_r && !portal_transparent)
                    // Portal sprite
                    begin red = portal_pixel[23:16]; green = portal_pixel[15:8]; blue = portal_pixel[7:0]; end
                else if (in_image_r) begin
                    if (pixel_data_r)       begin red = 8'h00; green = 8'h00; blue = 8'hFF; end // Wall — blue
                    else if (dot_alive_r)   begin red = 8'hFF; green = 8'hFF; blue = 8'h00; end // Dot — yellow
                    else                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end // Floor — white
                end else
                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end // Outside active display — white
            end

            // Default: black screen for any undefined state
            default: begin red = 8'h00; green = 8'h00; blue = 8'h00; end

        endcase
    end

endmodule
