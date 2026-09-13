// ---------------------------------------------------------------------------
// traffic_light_top : DE1-SoC traffic light controller, top level.
//
// Target: Cyclone V 5CSEMA5F31C6N (Terasic DE1-SoC)
//
// LED map (matches constraints/pins.qsf):
//   LEDR[0] NS red     LEDR[3] EW red
//   LEDR[1] NS yellow  LEDR[4] EW yellow
//   LEDR[2] NS green   LEDR[5] EW green
//   LEDR[6] WALK
// HEX0 shows seconds remaining in the current phase.
//
// Input path: KEY -> invert (active low) -> 2FF synchroniser -> debouncer
//             -> edge pulse -> FSM. Nothing asynchronous reaches the FSM.
// ---------------------------------------------------------------------------
module traffic_light_top #(
    parameter integer DIV_MAX      = 49_999_999,  // 1 Hz from 50 MHz
    parameter integer DEBOUNCE_CNT = 500_000,     // 10 ms at 50 MHz
    parameter integer T_GREEN      = 7,
    parameter integer T_YELLOW     = 2,
    parameter integer T_ALLRED     = 1,
    parameter integer T_WALK       = 4
)(
    input  wire       CLOCK_50,
    input  wire       KEY0,        // active low - reset
    input  wire       KEY1,        // active low - pedestrian request
    output wire [9:0] LEDR,
    output wire [6:0] HEX0
);

    wire rst;
    wire ped_raw, ped_sync, ped_clean, ped_pulse;
    wire tick;
    wire ns_g, ns_y, ns_r, ew_g, ew_y, ew_r, walk;
    wire [3:0] countdown;
    wire [2:0] state;

    // ---- reset: async assert, sync de-assert ------------------------------
    reset_sync u_rst (
        .clk         (CLOCK_50),
        .async_rst_n (KEY0),
        .rst         (rst)
    );

    // ---- pedestrian button: synchronise, then debounce, then edge-detect --
    assign ped_raw = ~KEY1;      // KEY is active low

    sync_2ff u_ped_sync (
        .clk (CLOCK_50),
        .rst (rst),
        .d   (ped_raw),
        .q   (ped_sync)
    );

    debouncer #(.CNT_MAX(DEBOUNCE_CNT)) u_ped_db (
        .clk   (CLOCK_50),
        .rst   (rst),
        .noisy (ped_sync),
        .clean (ped_clean),
        .rise  (ped_pulse)
    );

    // ---- 1 Hz timebase ----------------------------------------------------
    clk_div #(.DIV_MAX(DIV_MAX)) u_div (
        .clk  (CLOCK_50),
        .rst  (rst),
        .tick (tick)
    );

    // ---- control ----------------------------------------------------------
    traffic_fsm #(
        .T_GREEN  (T_GREEN),
        .T_YELLOW (T_YELLOW),
        .T_ALLRED (T_ALLRED),
        .T_WALK   (T_WALK)
    ) u_fsm (
        .clk       (CLOCK_50),
        .rst       (rst),
        .tick      (tick),
        .ped_pulse (ped_pulse),
        .ns_g (ns_g), .ns_y (ns_y), .ns_r (ns_r),
        .ew_g (ew_g), .ew_y (ew_y), .ew_r (ew_r),
        .walk      (walk),
        .countdown (countdown),
        .state_o   (state)
    );

    // ---- display ----------------------------------------------------------
    seven_seg u_seg (
        .val (countdown),
        .seg (HEX0)
    );

    assign LEDR = {3'b000, walk, ew_g, ew_y, ew_r, ns_g, ns_y, ns_r};

endmodule
