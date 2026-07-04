module score_tracker (
    input  logic        clock,
    input  logic        reset_n,
    input  logic        dot_eaten, // pulses high for one cycle every time a dot pixel gets erased from the RAM
    output logic [15:0] score      // counts total dot pixels eaten — win triggers in display.sv when this hits 14256
);
    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n)
            score <= 0;          // reset score to 0 on power on
        else if (dot_eaten)
            score <= score + 1;  // every time a dot pixel is erased, add 1 to score
    end
endmodule