//module dot_state (
//    input  logic        clk,
//    input  logic        reset_n,
//    input  logic [18:0] read_addr,
//    output logic        dot_alive,
//    input  logic        eat,
//    input  logic [18:0] eat_addr
//);
//    (* ramstyle = "M9K" *) logic [0:0] mem [0:307199];
//    initial $readmemb("dots.hex", mem);
//
//    always_ff @(posedge clk) begin
//        if (eat)
//            mem[eat_addr] <= 1'b0;
//        dot_alive <= mem[read_addr];
//    end
//
//endmodule

module dot_state (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [18:0] read_addr, // pixel address from VGA beam — used to check if a dot should be displayed
    output logic        dot_alive, // 1 = dot pixel still exists here, 0 = already eaten
    input  logic        eat,       // high when pac-man is moving and eating
    input  logic [18:0] eat_addr,  // pixel address inside pac-man's eat area — one pixel checked per cycle
    output logic        dot_eaten  // pulses high when a dot pixel was just erased — goes to score_tracker
);
    // 307,200 slots — one per pixel on the 640x480 screen
    // each slot is 1 bit: 1 = dot here, 0 = no dot
    // loaded from dots.hex at power on which was generated from a Paint image using Python
    (* ramstyle = "M9K" *) logic [0:0] mem [0:307199];
    initial $readmemb("dots.hex", mem);

    logic was_dot; // remembers if the pixel at eat_addr was a dot BEFORE we erased it

    // write port — pac-man erasing dots
    // every cycle: save what was at eat_addr, then write 0 to erase it if eat is high
    always_ff @(posedge clk) begin
        was_dot <= mem[eat_addr]; // check if this pixel is currently a dot
        if (eat)
            mem[eat_addr] <= 1'b0; // erase it — overwrite with 0
    end

    // read port — telling the screen whether to draw a yellow dot at this pixel
    // pattern_generator reads dot_alive every cycle to decide if the current pixel should be yellow
    always_ff @(posedge clk)
        dot_alive <= mem[read_addr];

    // dot_eaten pulses high only when pac-man erased a pixel that was actually a dot
    // we need was_dot because eat fires over pac-man's whole body area including empty pixels
    // without this check, score would count empty pixels too
    always_ff @(posedge clk)
        dot_eaten <= eat && was_dot;

endmodule