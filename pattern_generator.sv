module pattern_generator(
    input  logic        vga_clock,
    input  logic        reset_n,
    input  logic [9:0]  hcount,
    input  logic [9:0]  vcount,
    input  logic [9:0]  pac_x,    pac_y,
    input  logic [9:0]  ghost_x,  ghost_y,
    input  logic [9:0]  rghost_x, rghost_y,
    input  logic [9:0]  ghost3_x, ghost3_y,
    input  logic [9:0]  ghost4_x, ghost4_y,
    input  logic [1:0]  direction,
    input  logic [1:0]  ghost_dir,
    input  logic [1:0]  ghost2_dir,
    input  logic [1:0]  ghost3_dir,
    input  logic [1:0]  ghost4_dir,
    input  logic        pixel_data,
    input  logic        dot_alive,
    input  logic        game_over,
    input  logic        win,
    input  logic        title_active,
    input  logic        title_pixel,
    input  logic        lose_pixel,
    input  logic        win_pixel,
    input  logic [1:0]  game_state,
    output logic [18:0] vga_addr,
    output logic [7:0]  red, green, blue
);
    localparam IMG_W      = 10'd640;
    localparam IMG_H      = 10'd480;
    localparam PAC_SIZE   = 10'd32;
    localparam GHOST_SIZE = 10'd32;
    localparam DIR_LEFT   = 2'd0;
    localparam DIR_RIGHT  = 2'd1;
    localparam DIR_UP     = 2'd2;
    localparam DIR_DOWN   = 2'd3;

    localparam PORTAL_X    = 10'd288;
    localparam PORTAL_Y    = 10'd204;
    localparam PORTAL_SIZE = 10'd64;

    localparam TITLE_X0 = 10'd160;
    localparam TITLE_X1 = 10'd480;
    localparam TITLE_Y0 = 10'd120;
    localparam TITLE_Y1 = 10'd360;

    localparam S_TITLE   = 2'd0;
    localparam S_PLAYING = 2'd1;
    localparam S_LOSE    = 2'd2;
    localparam S_WIN     = 2'd3;

    logic        in_image, in_image_r;
    logic        pixel_data_r, dot_alive_r;
    logic        game_over_r, win_r, title_active_r;
    logic [1:0]  game_state_r;
    logic        title_pixel_r, lose_pixel_r, win_pixel_r;
    logic        in_title, in_title_r, in_title_rr;
    logic        pac_visible,    pac_visible_r;
    logic        ghost_visible,  ghost_visible_r;
    logic        rghost_visible, rghost_visible_r;
    logic        ghost3_visible, ghost3_visible_r;
    logic        ghost4_visible, ghost4_visible_r;
    logic        portal_visible, portal_visible_r;
    logic [12:0] sprite_addr;
    logic [11:0] ghost_sprite_addr, rghost_sprite_addr, ghost3_sprite_addr, ghost4_sprite_addr;
    logic [11:0] portal_sprite_addr;
    logic [23:0] sprite_pixel, ghost_pixel, rghost_pixel, ghost3_pixel, ghost4_pixel, portal_pixel;
    logic        ghost_transparent, rghost_transparent, ghost3_transparent, ghost4_transparent;
    logic        portal_transparent;
    logic [21:0] anim_cnt;
    logic        frame;
    logic [2:0]  anim_frame;
    logic [9:0]  ghost_x_r,  ghost_y_r;
    logic [9:0]  rghost_x_r, rghost_y_r;
    logic [9:0]  ghost3_x_r, ghost3_y_r;
    logic [9:0]  ghost4_x_r, ghost4_y_r;
    logic [1:0]  ghost_dir_r, ghost2_dir_r, ghost3_dir_r, ghost4_dir_r;

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

    assign in_image      = (hcount < IMG_W && vcount < IMG_H);
    assign vga_addr      = 19'(vcount) * 19'd640 + 19'(hcount);
    assign in_title      = (hcount >= TITLE_X0 && hcount < TITLE_X1 &&
                            vcount >= TITLE_Y0  && vcount < TITLE_Y1);

    assign pac_visible   = (hcount >= pac_x     && hcount < pac_x     + PAC_SIZE    && vcount >= pac_y     && vcount < pac_y     + PAC_SIZE);
    assign ghost_visible = (hcount >= ghost_x_r  && hcount < ghost_x_r  + GHOST_SIZE && vcount >= ghost_y_r  && vcount < ghost_y_r  + GHOST_SIZE);
    assign rghost_visible= (hcount >= rghost_x_r && hcount < rghost_x_r + GHOST_SIZE && vcount >= rghost_y_r && vcount < rghost_y_r + GHOST_SIZE);
    assign ghost3_visible= (hcount >= ghost3_x_r && hcount < ghost3_x_r + GHOST_SIZE && vcount >= ghost3_y_r && vcount < ghost3_y_r + GHOST_SIZE);
    assign ghost4_visible= (hcount >= ghost4_x_r && hcount < ghost4_x_r + GHOST_SIZE && vcount >= ghost4_y_r && vcount < ghost4_y_r + GHOST_SIZE);
    assign portal_visible= (hcount >= PORTAL_X   && hcount < PORTAL_X   + PORTAL_SIZE &&
                            vcount >= PORTAL_Y    && vcount < PORTAL_Y   + PORTAL_SIZE);

    assign ghost_transparent  = (ghost_pixel  == 24'hFF00FF) || (ghost_pixel[23:16]  > 8'hE0 && ghost_pixel[15:8]  > 8'hE0 && ghost_pixel[7:0]  > 8'hE0);
    assign rghost_transparent = (rghost_pixel == 24'hFF00FF) || (rghost_pixel[23:16] > 8'hE0 && rghost_pixel[15:8] > 8'hE0 && rghost_pixel[7:0] > 8'hE0);
    assign ghost3_transparent = (ghost3_pixel == 24'hFF00FF) || (ghost3_pixel[23:16] > 8'hE0 && ghost3_pixel[15:8] > 8'hE0 && ghost3_pixel[7:0] > 8'hE0);
    assign ghost4_transparent = (ghost4_pixel == 24'hFF00FF) || (ghost4_pixel[23:16] > 8'hE0 && ghost4_pixel[15:8] > 8'hE0 && ghost4_pixel[7:0] > 8'hE0);
    assign portal_transparent = (portal_pixel == 24'hFF00FF) || (portal_pixel[23:16] > 8'hE0 && portal_pixel[15:8] > 8'hE0 && portal_pixel[7:0] > 8'hE0);

    always_comb begin
        case (direction)
            DIR_RIGHT: anim_frame = {2'd0, frame};
            DIR_LEFT:  anim_frame = {2'd1, frame};
            DIR_UP:    anim_frame = {2'd2, frame};
            DIR_DOWN:  anim_frame = {2'd3, frame};
            default:   anim_frame = {2'd0, frame};
        endcase
    end

    assign sprite_addr        = 13'(anim_frame)   * 13'd1024 + 13'(vcount - pac_y)      * 13'd32 + 13'(hcount - pac_x);
    assign ghost_sprite_addr  = 12'(ghost_dir_r)  * 12'd1024 + 12'(vcount - ghost_y_r)  * 12'd32 + 12'(hcount - ghost_x_r);
    assign rghost_sprite_addr = 12'(ghost2_dir_r) * 12'd1024 + 12'(vcount - rghost_y_r) * 12'd32 + 12'(hcount - rghost_x_r);
    assign ghost3_sprite_addr = 12'(ghost3_dir_r) * 12'd1024 + 12'(vcount - ghost3_y_r) * 12'd32 + 12'(hcount - ghost3_x_r);
    assign ghost4_sprite_addr = 12'(ghost4_dir_r) * 12'd1024 + 12'(vcount - ghost4_y_r) * 12'd32 + 12'(hcount - ghost4_x_r);
    assign portal_sprite_addr = 12'(vcount - PORTAL_Y) * 12'd64 + 12'(hcount - PORTAL_X);

    always_ff @(posedge vga_clock or negedge reset_n) begin
        if (!reset_n) begin anim_cnt <= 0; frame <= 0; end
        else begin
            anim_cnt <= anim_cnt + 1;
            if (anim_cnt == 22'd3000000) begin anim_cnt <= 0; frame <= ~frame; end
        end
    end

    always_ff @(posedge vga_clock) begin
        in_image_r       <= in_image;
        in_title_r       <= in_title;
        in_title_rr      <= in_title_r;
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

    sprite_rom  sprite_inst        (.clk(vga_clock), .addr(sprite_addr),        .pixel_out(sprite_pixel));
    ghost_rom   ghost_sprite_inst  (.clk(vga_clock), .addr(ghost_sprite_addr),  .pixel_out(ghost_pixel));
    ghost2_rom  ghost2_sprite_inst (.clk(vga_clock), .addr(rghost_sprite_addr), .pixel_out(rghost_pixel));
    ghost3_rom  ghost3_sprite_inst (.clk(vga_clock), .addr(ghost3_sprite_addr), .pixel_out(ghost3_pixel));
    ghost4_rom  ghost4_sprite_inst (.clk(vga_clock), .addr(ghost4_sprite_addr), .pixel_out(ghost4_pixel));
    portal_rom  portal_inst        (.clk(vga_clock), .addr(portal_sprite_addr), .pixel_out(portal_pixel));

    always_comb begin
        case (game_state_r)
            S_TITLE: begin
                if (in_title_rr && title_pixel_r)
                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end
                else
                    begin red = 8'h00; green = 8'h00; blue = 8'h00; end
            end
            S_LOSE: begin
                if (in_title_rr && lose_pixel_r)
                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end
                else
                    begin red = 8'h00; green = 8'h00; blue = 8'h00; end
            end
            S_WIN: begin
                if (in_title_rr && win_pixel_r) //Checks if in 320 by 240 and win pixel 1 is white
                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end
                else
                    begin red = 8'h00; green = 8'h00; blue = 8'h00; end
            end
            S_PLAYING: begin
                if (pac_visible_r && sprite_pixel != 24'hFF00FF)
                    begin red = sprite_pixel[23:16]; green = sprite_pixel[15:8]; blue = sprite_pixel[7:0]; end
                else if (ghost_visible_r && !ghost_transparent)
                    begin red = ghost_pixel[23:16]; green = ghost_pixel[15:8]; blue = ghost_pixel[7:0]; end
                else if (rghost_visible_r && !rghost_transparent)
                    begin red = rghost_pixel[23:16]; green = rghost_pixel[15:8]; blue = rghost_pixel[7:0]; end
                else if (ghost3_visible_r && !ghost3_transparent)
                    begin red = ghost3_pixel[23:16]; green = ghost3_pixel[15:8]; blue = ghost3_pixel[7:0]; end
                else if (ghost4_visible_r && !ghost4_transparent)
                    begin red = ghost4_pixel[23:16]; green = ghost4_pixel[15:8]; blue = ghost4_pixel[7:0]; end
                else if (portal_visible_r && !portal_transparent)
                    begin red = portal_pixel[23:16]; green = portal_pixel[15:8]; blue = portal_pixel[7:0]; end
                else if (in_image_r) begin
                    if (pixel_data_r)       begin red = 8'h00; green = 8'h00; blue = 8'hFF; end
                    else if (dot_alive_r)   begin red = 8'hFF; green = 8'hFF; blue = 8'h00; end
                    else                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end
                end else
                    begin red = 8'hFF; green = 8'hFF; blue = 8'hFF; end
            end
            default: begin red = 8'h00; green = 8'h00; blue = 8'h00; end
        endcase
    end

endmodule