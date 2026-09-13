// ---------------------------------------------------------------------------
// traffic_fsm : 8-state Moore FSM for a two-way intersection + pedestrian walk.
//
// FIXES vs. the original design:
//
//  BUG 1 - off-by-one phase duration.
//    Original counted UP and transitioned on (timer == N), which gives N+1
//    ticks: a "7 second" green actually ran 8 seconds and the display showed
//    a trailing 0. Replaced with a DOWN counter loaded on state entry that
//    transitions when sec_left == 1, giving exactly N ticks and a display
//    that runs N..1 with no trailing zero.
//
//  BUG 2 - conflicting greens.
//    Original drove raw LEDR bit patterns whose polarity contradicted the pin
//    table, so the all-red interlock actually asserted BOTH greens. Fixed
//    structurally: outputs are named signals (ns_g/ns_y/ns_r/...) defaulting
//    to all-red, so no case arm CAN assert two greens. A bug of that class is
//    now unrepresentable rather than merely absent.
//
//  BUG 3 - pedestrian starvation.
//    Original latched the button on LEVEL with set-priority, so a held button
//    routed every interlock straight back into WALK and vehicles starved.
//    Now driven by a one-clock edge pulse from the debouncer.
//
//  BUG 4 - east-west starvation (found while fixing 3).
//    Original had one WALK state that always returned to NS_GREEN, so a
//    pedestrian request during the NS phase skipped the EW green entirely.
//    Split into WALK_1 (returns to EW) and WALK_2 (returns to NS).
//
// All 8 state encodings are used, so there is no unreachable illegal state.
// ---------------------------------------------------------------------------
module traffic_fsm #(
    parameter integer T_GREEN  = 7,   // seconds
    parameter integer T_YELLOW = 2,
    parameter integer T_ALLRED = 1,   // clearance interval - now explicit
    parameter integer T_WALK   = 4
)(
    input  wire       clk,
    input  wire       rst,            // synchronous, active high
    input  wire       tick,           // 1 Hz enable pulse
    input  wire       ped_pulse,      // 1-clock pulse, one per button press

    output reg        ns_g, ns_y, ns_r,
    output reg        ew_g, ew_y, ew_r,
    output reg        walk,
    output wire [3:0] countdown,      // seconds remaining in current phase
    output wire [2:0] state_o         // exported for waveform debug only
);

    localparam [2:0] S_NS_GREEN = 3'd0,
                     S_NS_YEL   = 3'd1,
                     S_AR_1     = 3'd2,   // all-red clearance, NS -> EW
                     S_WALK_1   = 3'd3,   // walk, then EW green
                     S_EW_GREEN = 3'd4,
                     S_EW_YEL   = 3'd5,
                     S_AR_2     = 3'd6,   // all-red clearance, EW -> NS
                     S_WALK_2   = 3'd7;   // walk, then NS green

    reg [2:0] state, next_state;
    reg [3:0] sec_left;
    reg       ped_pending;

    assign state_o   = state;
    assign countdown = sec_left;

    // ---- phase duration lookup -------------------------------------------
    function [3:0] duration;
        input [2:0] s;
        begin
            case (s)
                S_NS_GREEN, S_EW_GREEN: duration = T_GREEN;
                S_NS_YEL,   S_EW_YEL:   duration = T_YELLOW;
                S_AR_1,     S_AR_2:     duration = T_ALLRED;
                S_WALK_1,   S_WALK_2:   duration = T_WALK;
                default:                duration = 4'd1;
            endcase
        end
    endfunction

    // ---- next-state logic -------------------------------------------------
    always @(*) begin
        case (state)
            S_NS_GREEN: next_state = S_NS_YEL;
            S_NS_YEL  : next_state = S_AR_1;
            S_AR_1    : next_state = ped_pending ? S_WALK_1 : S_EW_GREEN;
            S_WALK_1  : next_state = S_EW_GREEN;
            S_EW_GREEN: next_state = S_EW_YEL;
            S_EW_YEL  : next_state = S_AR_2;
            S_AR_2    : next_state = ped_pending ? S_WALK_2 : S_NS_GREEN;
            S_WALK_2  : next_state = S_NS_GREEN;
            default   : next_state = S_NS_GREEN;
        endcase
    end

    // ---- pedestrian request latch ----------------------------------------
    // Cleared on entry to a walk phase. ped_pulse keeps set-priority so a
    // press landing on that exact edge queues the NEXT walk instead of being
    // swallowed - safe now that the pulse is one clock wide.
    wire entering_walk = tick && (sec_left <= 4'd1) &&
                         ((next_state == S_WALK_1) || (next_state == S_WALK_2));

    always @(posedge clk) begin
        if (rst)               ped_pending <= 1'b0;
        else if (ped_pulse)    ped_pending <= 1'b1;
        else if (entering_walk) ped_pending <= 1'b0;
    end

    // ---- state register + down counter ------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state    <= S_NS_GREEN;
            sec_left <= duration(S_NS_GREEN);
        end else if (tick) begin
            if (sec_left <= 4'd1) begin
                state    <= next_state;
                sec_left <= duration(next_state);
            end else begin
                sec_left <= sec_left - 4'd1;
            end
        end
    end

    // ---- output decode (Moore) --------------------------------------------
    // Default is ALL RED. Only the active direction is lifted out of red, so
    // two greens cannot be asserted by construction.
    always @(*) begin
        ns_g = 1'b0; ns_y = 1'b0; ns_r = 1'b1;
        ew_g = 1'b0; ew_y = 1'b0; ew_r = 1'b1;
        walk = 1'b0;

        case (state)
            S_NS_GREEN        : begin ns_g = 1'b1; ns_r = 1'b0; end
            S_NS_YEL          : begin ns_y = 1'b1; ns_r = 1'b0; end
            S_EW_GREEN        : begin ew_g = 1'b1; ew_r = 1'b0; end
            S_EW_YEL          : begin ew_y = 1'b1; ew_r = 1'b0; end
            S_WALK_1, S_WALK_2: walk = 1'b1;
            default           : ;   // S_AR_1 / S_AR_2 keep the all-red default
        endcase
    end

endmodule
