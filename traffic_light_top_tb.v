`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// traffic_light_top_tb : self-checking testbench.
//
// The original testbench used $monitor and required a human to read a console
// dump and decide whether it looked right. This one PASSES or FAILS on its
// own and prints an error count.
//
// Key point: every safety assertion checks the OUTPUT PINS, not the internal
// FSM state. An assertion written against 'state' would have completely
// missed the conflicting-greens bug, because the state sequence was correct
// all along - it was the output decode that was wrong.
//
// DIV_MAX is overridden to 4, so one simulated "second" is 100 ns instead of
// 1 s. Identical logic, ~5,000,000x faster.
// ---------------------------------------------------------------------------
module traffic_light_top_tb;

    localparam integer CLK_PERIOD   = 20;      // 20 ns -> 50 MHz
    localparam integer DIV_MAX      = 4;       // tick every 5 clocks
    localparam integer DEBOUNCE_CNT = 3;
    localparam integer SEC_NS       = (DIV_MAX + 1) * CLK_PERIOD;   // 100 ns

    localparam integer T_GREEN  = 7;
    localparam integer T_YELLOW = 2;
    localparam integer T_ALLRED = 1;
    localparam integer T_WALK   = 4;

    reg         CLOCK_50 = 1'b0;
    reg         KEY0     = 1'b1;   // active low reset
    reg         KEY1     = 1'b1;   // active low pedestrian
    wire [9:0]  LEDR;
    wire [6:0]  HEX0;

    integer errors    = 0;
    integer checking  = 0;
    integer walks     = 0;
    integer ew_greens = 0;
    integer ns_greens = 0;

    // named views of the output pins
    wire ns_r = LEDR[0], ns_y = LEDR[1], ns_g = LEDR[2];
    wire ew_r = LEDR[3], ew_y = LEDR[4], ew_g = LEDR[5];
    wire walk = LEDR[6];
    wire [6:0] leds = LEDR[6:0];

    traffic_light_top #(
        .DIV_MAX      (DIV_MAX),
        .DEBOUNCE_CNT (DEBOUNCE_CNT),
        .T_GREEN      (T_GREEN),
        .T_YELLOW     (T_YELLOW),
        .T_ALLRED     (T_ALLRED),
        .T_WALK       (T_WALK)
    ) dut (
        .CLOCK_50 (CLOCK_50),
        .KEY0     (KEY0),
        .KEY1     (KEY1),
        .LEDR     (LEDR),
        .HEX0     (HEX0)
    );

    always #(CLK_PERIOD/2) CLOCK_50 = ~CLOCK_50;

    task fail(input [1023:0] msg);
        begin
            $display("  [FAIL] %0t ns : %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // =======================================================================
    // SAFETY ASSERTIONS - checked continuously, on output pins
    // =======================================================================

    // A1: the two directions must never both show green. This is THE safety
    //     property of an intersection controller.
    always @(posedge CLOCK_50) if (checking) begin
        if (ns_g && ew_g) fail("A1 conflicting greens NS_G and EW_G both high");
    end

    // A2: a green must never coincide with the same direction's red.
    always @(posedge CLOCK_50) if (checking) begin
        if (ns_g && ns_r) fail("A2 NS green and NS red simultaneously");
        if (ew_g && ew_r) fail("A2 EW green and EW red simultaneously");
    end

    // A3: WALK may only be asserted when BOTH directions are fully red.
    always @(posedge CLOCK_50) if (checking) begin
        if (walk && !(ns_r && ew_r))
            fail("A3 WALK asserted while a vehicle phase is not red");
    end

    // A4: exactly one aspect lit per direction at all times.
    always @(posedge CLOCK_50) if (checking) begin
        if ((ns_r + ns_y + ns_g) != 1) fail("A4 NS does not show exactly one aspect");
        if ((ew_r + ew_y + ew_g) != 1) fail("A4 EW does not show exactly one aspect");
    end

    // A5: countdown must never display a value above the longest phase.
    always @(posedge CLOCK_50) if (checking) begin
        if (dut.countdown > T_GREEN[3:0]) fail("A5 countdown exceeds longest phase");
        if (dut.countdown == 4'd0)        fail("A5 countdown showed trailing zero");
    end

    // =======================================================================
    // PHASE DURATION CHECKER - catches the off-by-one bug
    // =======================================================================
    function integer expected_secs(input [6:0] l);
        begin
            if      (l[6])           expected_secs = T_WALK;
            else if (l[2] || l[5])   expected_secs = T_GREEN;
            else if (l[1] || l[4])   expected_secs = T_YELLOW;
            else                     expected_secs = T_ALLRED;
        end
    endfunction

    reg [6:0] prev_leds;
    time      last_change;
    integer   measured;
    integer   phases = 0;
    integer   armed  = 0;   // a phase truncated by reset has no meaningful length

    always @(negedge KEY0) armed = 0;

    always @(posedge KEY0) begin
        armed       = 0;
        last_change = $time;
        prev_leds   = leds;
    end

    always @(leds) begin
        if (checking && armed) begin
            // round rather than truncate so a sub-tick offset is not reported
            // as a whole second of error
            measured = ($time - last_change + SEC_NS/2) / SEC_NS;
            if (measured != expected_secs(prev_leds)) begin
                $display("  [FAIL] %0t ns : phase %b lasted %0d s, expected %0d s",
                         $time, prev_leds, measured, expected_secs(prev_leds));
                errors = errors + 1;
            end
            phases = phases + 1;
        end
        last_change = $time;
        prev_leds   = leds;
        armed       = 1;
    end

    // activity counters
    always @(posedge CLOCK_50) if (checking) begin
        if (walk && !past_walk) walks     = walks     + 1;
        if (ew_g && !past_ewg)  ew_greens = ew_greens + 1;
        if (ns_g && !past_nsg)  ns_greens = ns_greens + 1;
    end
    reg past_walk = 0, past_ewg = 0, past_nsg = 0;
    always @(posedge CLOCK_50) begin
        past_walk <= walk; past_ewg <= ew_g; past_nsg <= ns_g;
    end

    // =======================================================================
    // STIMULUS
    // =======================================================================
    task press_clean(input integer hold_ns);
        begin
            KEY1 = 1'b0;
            #(hold_ns);
            KEY1 = 1'b1;
        end
    endtask

    // Models real contact chatter: random toggles for the first ~bounce window.
    task press_bouncy;
        integer i;
        begin
            for (i = 0; i < 40; i = i + 1) begin
                KEY1 = $random;
                #(CLK_PERIOD);
            end
            KEY1 = 1'b0;            // settle closed
            #(20 * CLK_PERIOD);
            for (i = 0; i < 40; i = i + 1) begin
                KEY1 = $random;
                #(CLK_PERIOD);
            end
            KEY1 = 1'b1;            // settle open
        end
    endtask

    integer w0, e0;

    initial begin
        $dumpfile("tlc.vcd");
        $dumpvars(0, traffic_light_top_tb);

        $display("");
        $display("=== Traffic Light Controller regression ===");

        // ---- reset ---------------------------------------------------------
        KEY0 = 1'b0;
        repeat (10) @(posedge CLOCK_50);
        KEY0 = 1'b1;
        repeat (5) @(posedge CLOCK_50);
        last_change = $time;
        prev_leds   = leds;
        checking    = 1;
        armed       = 0;

        // ---- TEST 1 : free-running, no pedestrian --------------------------
        $display("T1  free-running cycles, no pedestrian request");
        w0 = walks;
        #(60 * SEC_NS);
        if (walks != w0) fail("T1 walk phase occurred with no button press");

        // ---- TEST 2 : one clean press --------------------------------------
        $display("T2  single clean press -> exactly one walk phase");
        w0 = walks; e0 = ew_greens;
        press_clean(10 * CLK_PERIOD);
        #(40 * SEC_NS);
        if (walks - w0 != 1)
            fail("T2 expected exactly 1 walk phase after one press");
        if (ew_greens - e0 < 1)
            fail("T2 EW green was skipped after a pedestrian walk (starvation)");

        // ---- TEST 3 : bouncy press ----------------------------------------
        $display("T3  bouncing contacts -> still exactly one walk phase");
        w0 = walks;
        press_bouncy;
        #(40 * SEC_NS);
        if (walks - w0 != 1)
            fail("T3 contact bounce produced the wrong number of walk phases");

        // ---- TEST 4 : button held down (starvation test) -------------------
        $display("T4  button held for 3 full cycles -> vehicles must not starve");
        w0 = walks; e0 = ew_greens;
        KEY1 = 1'b0;
        #(70 * SEC_NS);
        KEY1 = 1'b1;
        #(10 * SEC_NS);
        if (walks - w0 != 1)
            fail("T4 held button produced repeated walk phases (starvation)");
        if (ew_greens - e0 < 2)
            fail("T4 EW traffic starved while button was held");

        // ---- TEST 5 : reset mid-cycle --------------------------------------
        $display("T5  asynchronous reset returns to NS green");
        KEY0 = 1'b0;
        #(3 * CLK_PERIOD);
        KEY0 = 1'b1;
        @(posedge CLOCK_50);
        repeat (4) @(posedge CLOCK_50);
        if (!ns_g) fail("T5 reset did not return the FSM to NS green");
        last_change = $time;
        prev_leds   = leds;
        #(30 * SEC_NS);

        // ---- summary -------------------------------------------------------
        $display("");
        $display("phases checked : %0d", phases);
        $display("walk phases    : %0d", walks);
        $display("NS greens      : %0d", ns_greens);
        $display("EW greens      : %0d", ew_greens);
        if (errors == 0) $display("RESULT : PASS  (0 errors)");
        else             $display("RESULT : FAIL  (%0d errors)", errors);
        $display("");
        $finish;
    end

endmodule
