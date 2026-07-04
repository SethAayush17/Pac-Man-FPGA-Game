module pac_controller(
    input  logic        clock,
    input  logic        reset_n,
    input  logic [11:0] joystick_lr,
    input  logic [11:0] joystick_ud,
    output logic [9:0]  pac_x,
    output logic [9:0]  pac_y,
    output logic [1:0]  direction,
    output logic [18:0] col_addr,
    input  logic        col_pixel,
    output logic        eat,
    output logic [18:0] eat_addr,
    output logic        moving_out,
    output logic [9:0]  pac_tile_x,
    output logic [9:0]  pac_tile_y
);
    localparam PAC_SIZE  = 10'd32;
    localparam TILE_W    = 10'd23;
    localparam TILE_H    = 10'd16;
    localparam [9:0] START_X = 10'd305;
    localparam [9:0] START_Y = 10'd212;

    localparam TUNNEL_Y_MIN = 10'd200;
    localparam TUNNEL_Y_MAX = 10'd279;

    localparam DIR_LEFT  = 2'd0;
    localparam DIR_RIGHT = 2'd1;
    localparam DIR_UP    = 2'd2;
    localparam DIR_DOWN  = 2'd3;

    logic [19:0] speed_cnt;
    logic        move_en;
    logic [1:0]  next_dir;
    logic [31:0] col_addr_full;
    logic        moving;
    logic [1:0]  check_cnt;
    logic        wall_hit;
    logic        prev_wall_hit;
    logic [4:0]  eat_x_cnt, eat_y_cnt;
    logic        in_tunnel;

    assign move_en    = (speed_cnt == 20'd400000);
    assign moving_out = moving;
    assign pac_tile_x = (pac_x + PAC_SIZE/2) / TILE_W;
    assign pac_tile_y = (pac_y + PAC_SIZE/2) / TILE_H;
    assign in_tunnel  = (pac_y >= TUNNEL_Y_MIN && pac_y <= TUNNEL_Y_MAX);

    assign eat_addr = 19'(pac_y + 19'(eat_y_cnt)) * 19'd640 +
                      19'(pac_x + 19'(eat_x_cnt));
    assign eat = moving;

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
            next_dir = direction;
    end

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
                    2'd0: col_addr_full = 32'(pac_y) * 32'd640 + 32'(pac_x) + 32'd3;
                    2'd1: col_addr_full = 32'(pac_y) * 32'd640 + 32'(pac_x) + 32'(PAC_SIZE/2);
                    2'd2: col_addr_full = 32'(pac_y) * 32'd640 + 32'(pac_x) + 32'(PAC_SIZE) - 32'd3;
                    default: col_addr_full = 32'd0;
                endcase
            end
            DIR_DOWN: begin
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

    assign col_addr = col_addr_full[18:0];

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
                speed_cnt     <= 0;
                check_cnt     <= 0;
                prev_wall_hit <= wall_hit;
                wall_hit      <= 0;

                if (next_dir != direction) begin
                    direction <= next_dir;
                    moving    <= 1'b1;
                end

                if (moving && !prev_wall_hit) begin
                    case (direction)
                        DIR_LEFT:  if (pac_x > 0)       pac_x <= pac_x - 10'd1;
                        DIR_RIGHT: if (pac_x < 10'd608) pac_x <= pac_x + 10'd1;
                        DIR_UP:    if (pac_y > 0)        pac_y <= pac_y - 10'd1;
                        DIR_DOWN:  if (pac_y < 10'd448) pac_y <= pac_y + 10'd1;
                    endcase
                end

                if (moving && in_tunnel && direction == DIR_LEFT  && pac_x == 0)
                    pac_x <= 10'd608;
                if (moving && in_tunnel && direction == DIR_RIGHT && pac_x >= 10'd608)
                    pac_x <= 10'd0;

            end else begin
                check_cnt <= check_cnt + 1;
                if (check_cnt == 2'd0)
                    wall_hit <= col_pixel;
                else
                    wall_hit <= wall_hit | col_pixel;
            end
        end
    end

endmodule