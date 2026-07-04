// =============================================================================
// pwm2.sv — Pac-Man Theme PWM Audio Generator
// =============================================================================
// Generates the Pac-Man theme melody as a PWM square wave output by cycling
// through a hardcoded sequence of 40 notes, each with a defined frequency
// and duration.
//
// How PWM audio works:
//   A counter counts up to a rollover value derived from the note's frequency.
//   The output is high for the first half of the cycle and low for the second
//   half, producing a 50% duty cycle square wave at the target frequency.
//   The speaker converts this oscillation into an audible tone.
//
// Frequency encoding:
//   rollover = (clock_frequency / note_frequency)
//   At 50MHz: rollover for B4 (493.88Hz) = 50,000,000 / 493.88 ≈ 101,215
//   A rollover of 0 means silence — PWM output held low.
//
// Duration encoding:
//   W = 114,285,714 cycles = one whole note at ~120BPM (50MHz clock)
//   N8  = W/8  = one eighth note
//   N16 = W/16 = one sixteenth note
//   N32 = W/32 = one thirty-second note
//   D16 = N16 + N32 = dotted sixteenth note (1.5x duration)
//   GAP = 300,000 cycles = short silence between notes (~6ms)
//
// Playback:
//   duration_count tracks how long the current note has been playing.
//   When it reaches the note's duration, note_index advances to the next note.
//   After the last note (index 39), playback loops back to index 0.
//
// Note: increase/decrease inputs are present in the port list but unused —
// originally intended for runtime tempo control, not implemented.
// =============================================================================

module pwm2(
    // -------------------------------------------------------------------------
    // Clock and Reset
    // -------------------------------------------------------------------------
    input        clock,     // 50MHz system clock
    input        reset_n,   // Active-low reset — restarts melody from beginning

    // -------------------------------------------------------------------------
    // Unused Inputs (reserved for future tempo control)
    // -------------------------------------------------------------------------
    input        increase,  // Originally intended to increase tempo — not implemented
    input        decrease,  // Originally intended to decrease tempo — not implemented

    // -------------------------------------------------------------------------
    // PWM Output
    // -------------------------------------------------------------------------
    output logic pwm_out    // Square wave audio output — connect to speaker
);

    // -------------------------------------------------------------------------
    // Timing Constants
    // W = one whole note duration in clock cycles at ~120BPM (50MHz clock)
    // All note durations derived as fractions of W
    // -------------------------------------------------------------------------
    localparam W   = 32'd114_285_714; // Whole note: ~2.286 seconds at 50MHz
    localparam N8  = W / 8;           // Eighth note
    localparam N16 = W / 16;          // Sixteenth note
    localparam N32 = W / 32;          // Thirty-second note
    localparam D16 = N16 + N32;       // Dotted sixteenth note (1.5x sixteenth)
    localparam GAP = 32'd300_000;     // Short silence gap between notes (~6ms)

    // -------------------------------------------------------------------------
    // Note Sequence Tables
    // NUM_NOTES entries, each with a rollover (frequency) and duration value
    // rollover = 50,000,000 / note_frequency (in Hz)
    // rollover = 0 means silence for that entry
    // -------------------------------------------------------------------------
    localparam NUM_NOTES = 40;
    logic [31:0] rollover_table [0:NUM_NOTES-1]; // Frequency rollover per note
    logic [31:0] duration_table [0:NUM_NOTES-1]; // Duration in clock cycles per note

    initial begin
        // Note sequence: Pac-Man theme melody
        // Format: rollover_table[n] = frequency rollover, duration_table[n] = note length
        rollover_table[0]  = 32'd101_215; duration_table[0]  = N16; // B4
        rollover_table[1]  = 32'd50_607;  duration_table[1]  = N16; // B5
        rollover_table[2]  = 32'd67_568;  duration_table[2]  = N16; // F#5
        rollover_table[3]  = 32'd80_386;  duration_table[3]  = N16; // D#5
        rollover_table[4]  = 32'd50_607;  duration_table[4]  = N32; // B5
        rollover_table[5]  = 32'd67_568;  duration_table[5]  = D16; // F#5 dotted
        rollover_table[6]  = 32'd80_386;  duration_table[6]  = N8;  // D#5
        rollover_table[7]  = 32'd95_602;  duration_table[7]  = N16; // C5
        rollover_table[8]  = 32'd47_755;  duration_table[8]  = N16; // C6
        rollover_table[9]  = 32'd63_776;  duration_table[9]  = N16; // G5
        rollover_table[10] = 32'd75_873;  duration_table[10] = N16; // E5
        rollover_table[11] = 32'd47_755;  duration_table[11] = N32; // C6
        rollover_table[12] = 32'd63_776;  duration_table[12] = D16; // G5 dotted
        rollover_table[13] = 32'd75_873;  duration_table[13] = N8;  // E5
        rollover_table[14] = 32'd101_215; duration_table[14] = N16; // B4
        rollover_table[15] = 32'd50_607;  duration_table[15] = N16; // B5
        rollover_table[16] = 32'd67_568;  duration_table[16] = N16; // F#5
        rollover_table[17] = 32'd80_386;  duration_table[17] = N16; // D#5
        rollover_table[18] = 32'd50_607;  duration_table[18] = N32; // B5
        rollover_table[19] = 32'd67_568;  duration_table[19] = D16; // F#5 dotted
        rollover_table[20] = 32'd80_386;  duration_table[20] = N8;  // D#5
        rollover_table[21] = 32'd80_386;  duration_table[21] = N32; // D#5
        rollover_table[22] = 32'd75_873;  duration_table[22] = N32; // E5
        rollover_table[23] = 32'd71_633;  duration_table[23] = N32; // F5
        rollover_table[24] = 32'd0;       duration_table[24] = GAP; // silence
        rollover_table[25] = 32'd71_633;  duration_table[25] = N32; // F5
        rollover_table[26] = 32'd67_568;  duration_table[26] = N32; // F#5
        rollover_table[27] = 32'd63_776;  duration_table[27] = N32; // G5
        rollover_table[28] = 32'd0;       duration_table[28] = GAP; // silence
        rollover_table[29] = 32'd63_776;  duration_table[29] = N32; // G5
        rollover_table[30] = 32'd60_168;  duration_table[30] = N32; // G#5
        rollover_table[31] = 32'd56_818;  duration_table[31] = N16; // A5
        rollover_table[32] = 32'd50_607;  duration_table[32] = N8;  // B5
        rollover_table[33] = 32'd0;       duration_table[33] = N8;  // silence before loop

        // Fill remaining slots with silence
        for (int i = 34; i < NUM_NOTES; i++) begin
            rollover_table[i] = 32'd0;
            duration_table[i] = N32;
        end
    end

    // -------------------------------------------------------------------------
    // Playback State
    // -------------------------------------------------------------------------
    logic [5:0]  note_index;     // Current note being played (0 to NUM_NOTES-1)
    logic [31:0] duration_count; // Cycles elapsed on current note
    logic [31:0] rollover;       // Frequency rollover for current note
    logic [31:0] count;          // PWM cycle counter for frequency generation

    // Look up rollover value for the current note
    assign rollover = rollover_table[note_index];

    // -------------------------------------------------------------------------
    // Note Duration Sequencer
    // Advances note_index when duration_count reaches the current note's duration
    // Loops back to note 0 after the last note
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (!reset_n) begin
            note_index     <= '0;
            duration_count <= '0;
        end else begin
            if (duration_count >= duration_table[note_index] - 1) begin
                duration_count <= '0;
                // Advance to next note, wrap back to 0 after last note
                note_index <= (note_index == NUM_NOTES - 1) ? '0 : note_index + 1;
            end else begin
                duration_count <= duration_count + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // PWM Frequency Counter
    // Counts up to rollover and resets — one full cycle = one period of the note
    // For silence (rollover == 0), counter is held at 0 and output stays low
    // -------------------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (!reset_n)
            count <= '0;
        else if (rollover == 0 || count >= rollover - 1)
            count <= '0;
        else
            count <= count + 1;
    end

    // -------------------------------------------------------------------------
    // PWM Output
    // High for first half of the frequency cycle, low for second half
    // Produces a 50% duty cycle square wave at the target note frequency
    // Output is forced low when rollover == 0 (silence)
    // -------------------------------------------------------------------------
    assign pwm_out = (rollover != 0) && (count < (rollover >> 1));

endmodule
