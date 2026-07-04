module adc_controller (
    input  logic        system_clock,
    input  logic        reset_n,
    input  logic        sdo,
    output logic        cs_n,
    output logic        sclk,
    output logic        sdi,
    output logic [11:0] joystick_lr,
    output logic [11:0] joystick_ud
);
    localparam logic [2:0]
        START   = 3'd0,
        CONVERT = 3'd1,
        SCLK0   = 3'd2,
        SCLK1   = 3'd3,
        HOLD    = 3'd4;
    logic [2:0] state;
    logic [6:0] counter;
    logic [3:0] bit_idx;    
    localparam logic [11:0] CFG_CH5 = 12'b111010_000000;
    localparam logic [11:0] CFG_CH7 = 12'b111110_000000;

    logic        cur_ch;
    logic        next_ch;
    logic [11:0] sdi_shift;
    logic [11:0] sdo_shift;
    logic [11:0] lr_reg, ud_reg;
    always_ff @(posedge system_clock or negedge reset_n) begin
        if (!reset_n) begin
            state     <= START;
            counter   <= 7'd0;
            bit_idx   <= 4'd11;
            cur_ch    <= 1'b1;
            next_ch   <= 1'b0;
            sdi_shift <= CFG_CH5;
            sdo_shift <= 12'd0;
            lr_reg    <= 12'd0;
            ud_reg    <= 12'd0;
        end else begin
            case (state)

                START: begin
                    state   <= CONVERT;
                    counter <= 7'd78;
                end

                CONVERT: begin
                    if (counter == 7'd0) begin
                        state     <= SCLK0;
                        bit_idx   <= 4'd11;
                        sdo_shift <= 12'd0;
                        cur_ch    <= next_ch;
                        sdi_shift <= (next_ch == 1'b0) ? CFG_CH5 : CFG_CH7;
                        next_ch   <= ~next_ch;
                    end else begin
                        counter <= counter - 7'd1;
                    end
                end
                SCLK0: begin
                    sdo_shift[bit_idx] <= sdo;
                    state              <= SCLK1;
                end

                SCLK1: begin
                    sdi_shift <= {sdi_shift[10:0], 1'b0};
                    if (bit_idx == 4'd0) begin
                        if (cur_ch == 1'b0)
                            lr_reg <= sdo_shift;
                        else
                            ud_reg <= sdo_shift;
                        state <= HOLD;
                    end else begin
                        bit_idx <= bit_idx - 4'd1;
                        state   <= SCLK0;
                    end
                end
                HOLD: begin
                    state   <= START;
                    counter <= 7'd0;
                end
                default: begin
                    state   <= START;
                    counter <= 7'd0;
                end
            endcase
        end
    end

    assign cs_n = (state == START) ? 1'b1 : 1'b0;
    assign sclk = (state == SCLK1) ? 1'b1 : 1'b0;
    assign sdi  = ((state == SCLK0) || (state == SCLK1)) ? sdi_shift[11] : 1'b0;
    assign joystick_lr = lr_reg;
    assign joystick_ud = ud_reg;
endmodule