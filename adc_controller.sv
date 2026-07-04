// =============================================================================
// adc_controller.sv — SPI ADC Interface for Analog Joystick
// =============================================================================
// Reads two analog joystick axes (left/right and up/down) from an LTC2308
// ADC using a 4-wire SPI interface. Alternates between reading channel 5
// (left/right axis) and channel 7 (up/down axis) on each conversion cycle.
//
// SPI Protocol:
//   - CS_N low during conversion, high between conversions
//   - SCLK toggles once per bit (SCLK0 = low/sample, SCLK1 = high/shift)
//   - SDI sends 12-bit configuration word to select the channel
//   - SDO receives 12-bit conversion result MSB-first
//
// State Machine:
//   START   → Assert CS_N low, load counter for inter-conversion gap
//   CONVERT → Wait for counter to expire before starting SPI transfer
//   SCLK0   → SCLK low phase: sample SDO into shift register
//   SCLK1   → SCLK high phase: shift SDI out, decrement bit index
//   HOLD    → Latch completed result into lr_reg or ud_reg, return to START
//
// Channel alternation:
//   cur_ch = 0 → reading CH5 (left/right) → result stored in lr_reg
//   cur_ch = 1 → reading CH7 (up/down)    → result stored in ud_reg
//   next_ch toggles each conversion so channels alternate every cycle
//
// Output:
//   joystick_lr and joystick_ud are 12-bit values (0x000–0xFFF)
//   Midpoint (~0x800) = centered, <0x400 = negative, >0xC00 = positive
// =============================================================================

module adc_controller (
    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    input  logic        system_clock, // 50MHz system clock
    input  logic        reset_n,      // Active-low reset

    // -------------------------------------------------------------------------
    // SPI Interface (to LTC2308 ADC)
    // -------------------------------------------------------------------------
    input  logic        sdo,          // Serial data out from ADC (MISO)
    output logic        cs_n,         // Chip select active low (low during conversion)
    output logic        sclk,         // SPI clock (toggled during SCLK0/SCLK1 states)
    output logic        sdi,          // Serial data in to ADC (MOSI) — config word

    // -------------------------------------------------------------------------
    // Joystick Outputs
    // -------------------------------------------------------------------------
    output logic [11:0] joystick_lr,  // 12-bit left/right ADC result (CH5)
    output logic [11:0] joystick_ud   // 12-bit up/down ADC result (CH7)
);

    // -------------------------------------------------------------------------
    // State Encoding
    // -------------------------------------------------------------------------
    localparam logic [2:0]
        START   = 3'd0, // CS_N high, load inter-conversion delay counter
        CONVERT = 3'd1, // Wait for counter to reach 0 before SPI transfer
        SCLK0   = 3'd2, // SCLK low: sample SDO bit into sdo_shift
        SCLK1   = 3'd3, // SCLK high: shift sdi_shift out, decrement bit_idx
        HOLD    = 3'd4; // Latch result into lr_reg or ud_reg, return to START

    logic [2:0] state;

    // -------------------------------------------------------------------------
    // Timing and Bit Counters
    // -------------------------------------------------------------------------
    logic [6:0] counter; // Inter-conversion delay counter (counts down from 78)
    logic [3:0] bit_idx; // Current bit being transferred (11 down to 0, MSB first)

    // -------------------------------------------------------------------------
    // SPI Configuration Words (12-bit, sent MSB-first via SDI)
    // Format: [channel select bits][don't care bits]
    // CFG_CH5: selects channel 5 (joystick left/right axis)
    // CFG_CH7: selects channel 7 (joystick up/down axis)
    // -------------------------------------------------------------------------
    localparam logic [11:0] CFG_CH5 = 12'b111010_000000;
    localparam logic [11:0] CFG_CH7 = 12'b111110_000000;

    // -------------------------------------------------------------------------
    // Channel Alternation
    // cur_ch:  channel being read in the current conversion (0=CH5, 1=CH7)
    // next_ch: channel to read on the next conversion (toggled each cycle)
    // -------------------------------------------------------------------------
    logic        cur_ch;
    logic        next_ch;

    // -------------------------------------------------------------------------
    // SPI Shift Registers
    // sdi_shift: config word shifted out MSB-first to ADC during SCLK1
    // sdo_shift: conversion result shifted in MSB-first from ADC during SCLK0
    // -------------------------------------------------------------------------
    logic [11:0] sdi_shift;
    logic [11:0] sdo_shift;

    // -------------------------------------------------------------------------
    // Latched ADC Results
    // Updated at end of each conversion once all 12 bits are received
    // -------------------------------------------------------------------------
    logic [11:0] lr_reg, ud_reg;

    // -------------------------------------------------------------------------
    // SPI State Machine
    // -------------------------------------------------------------------------
    always_ff @(posedge system_clock or negedge reset_n) begin
        if (!reset_n) begin
            state     <= START;
            counter   <= 7'd0;
            bit_idx   <= 4'd11;
            cur_ch    <= 1'b1;          // Start by reading CH5 on first conversion
            next_ch   <= 1'b0;
            sdi_shift <= CFG_CH5;       // Preload CH5 config word
            sdo_shift <= 12'd0;
            lr_reg    <= 12'd0;
            ud_reg    <= 12'd0;
        end else begin
            case (state)

                // -----------------------------------------------------------------
                // START: Begin a new conversion cycle
                // Load inter-conversion gap counter and move to CONVERT
                // -----------------------------------------------------------------
                START: begin
                    state   <= CONVERT;
                    counter <= 7'd78; // Wait ~1.56us at 50MHz before SPI transfer
                end

                // -----------------------------------------------------------------
                // CONVERT: Wait for counter to expire
                // When done, load the correct config word for the next channel
                // and initialize the bit index for a fresh 12-bit transfer
                // -----------------------------------------------------------------
                CONVERT: begin
                    if (counter == 7'd0) begin
                        state     <= SCLK0;
                        bit_idx   <= 4'd11;          // Start from MSB
                        sdo_shift <= 12'd0;          // Clear incoming shift register
                        cur_ch    <= next_ch;        // Latch which channel to read
                        sdi_shift <= (next_ch == 1'b0) ? CFG_CH5 : CFG_CH7;
                        next_ch   <= ~next_ch;       // Toggle for next conversion
                    end else begin
                        counter <= counter - 7'd1;
                    end
                end

                // -----------------------------------------------------------------
                // SCLK0: SCLK low phase
                // Sample SDO (ADC output) into sdo_shift at current bit position
                // -----------------------------------------------------------------
                SCLK0: begin
                    sdo_shift[bit_idx] <= sdo;
                    state              <= SCLK1;
                end

                // -----------------------------------------------------------------
                // SCLK1: SCLK high phase
                // Shift sdi_shift left by 1 to present next config bit on SDI
                // If this was the last bit (bit_idx == 0), latch result and hold
                // Otherwise decrement bit_idx and return to SCLK0
                // -----------------------------------------------------------------
                SCLK1: begin
                    sdi_shift <= {sdi_shift[10:0], 1'b0}; // Shift config word left
                    if (bit_idx == 4'd0) begin
                        // All 12 bits received — store result in appropriate register
                        if (cur_ch == 1'b0)
                            lr_reg <= sdo_shift; // CH5 = left/right axis
                        else
                            ud_reg <= sdo_shift; // CH7 = up/down axis
                        state <= HOLD;
                    end else begin
                        bit_idx <= bit_idx - 4'd1;
                        state   <= SCLK0;
                    end
                end

                // -----------------------------------------------------------------
                // HOLD: One-cycle pause after conversion completes
                // Returns to START to begin the next channel's conversion
                // -----------------------------------------------------------------
                HOLD: begin
                    state   <= START;
                    counter <= 7'd0;
                end

                // Default: recover to START on any undefined state
                default: begin
                    state   <= START;
                    counter <= 7'd0;
                end

            endcase
        end
    end

    // -------------------------------------------------------------------------
    // SPI Output Signal Assignments
    // CS_N:  low during all states except START (active during conversion)
    // SCLK:  high only during SCLK1 phase (low during SCLK0 and idle)
    // SDI:   drives MSB of sdi_shift during SCLK0 and SCLK1, otherwise 0
    // -------------------------------------------------------------------------
    assign cs_n = (state == START) ? 1'b1 : 1'b0;
    assign sclk = (state == SCLK1) ? 1'b1 : 1'b0;
    assign sdi  = ((state == SCLK0) || (state == SCLK1)) ? sdi_shift[11] : 1'b0;

    // -------------------------------------------------------------------------
    // Joystick Output — directly driven from latched ADC result registers
    // -------------------------------------------------------------------------
    assign joystick_lr = lr_reg;
    assign joystick_ud = ud_reg;

endmodule
