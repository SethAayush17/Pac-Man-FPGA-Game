module vga_controller(
    input  logic        vga_clock,
    input  logic        reset_n,
    output logic        sync_n,
    output logic        blank_n,
    output logic        hsync_n,
    output logic        vsync_n,
    output logic [9:0]  hcount,
    output logic [9:0]  vcount
);
    always_ff @(posedge vga_clock or negedge reset_n) begin
        if (!reset_n)
            hcount <= 10'd0;
        else if (hcount == 10'd799)
            hcount <= 10'd0;
        else
            hcount <= hcount + 10'd1;
    end

    always_ff @(posedge vga_clock or negedge reset_n) begin
        if (!reset_n)
            vcount <= 10'd0;
        else if (hcount == 10'd799) begin
            if (vcount == 10'd524)
                vcount <= 10'd0;
            else
                vcount <= vcount + 10'd1;
        end
    end

    assign sync_n  = 1'b0;
    assign blank_n = (hcount < 10'd640) && (vcount < 10'd480);
    assign hsync_n = ~(hcount >= 10'd656 && hcount <= 10'd751);   //signal that signals to move on to next row
    assign vsync_n = ~(vcount >= 10'd490 && vcount <= 10'd491); 	// Signal that says that frame is done

endmodule