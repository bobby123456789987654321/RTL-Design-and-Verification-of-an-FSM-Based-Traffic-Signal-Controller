// ---------------------------------------------------------------------------
// debouncer : counter-based contact-bounce filter with edge detection.
//
// A push-button's contacts chatter for 1-10 ms after each press. The input
// must hold its new value for CNT_MAX consecutive clocks before that value is
// accepted; any glitch restarts the count.
//
// 'rise' is a ONE-CLOCK pulse on each accepted 0->1 transition. This is what
// fixes the held-button starvation bug: the original design latched on LEVEL,
// so holding the button re-armed the request forever and vehicles never got
// a full cycle. An edge pulse means one press == one request.
//
// CNT_MAX @ 50 MHz:  500_000 = 10 ms  (override to a small value for sim)
// ---------------------------------------------------------------------------
module debouncer #(
    parameter integer CNT_MAX = 500_000
)(
    input  wire clk,
    input  wire rst,       // synchronous, active high
    input  wire noisy,     // MUST already be synchronised (see sync_2ff)
    output reg  clean,
    output wire rise       // 1-clock pulse on accepted 0->1 edge
);

    localparam integer W = (CNT_MAX < 2) ? 1 : $clog2(CNT_MAX + 1);

    reg [W-1:0] cnt;
    reg         clean_d;

    always @(posedge clk) begin
        if (rst) begin
            cnt   <= {W{1'b0}};
            clean <= 1'b0;
        end else if (noisy == clean) begin
            cnt   <= {W{1'b0}};          // stable - hold
        end else if (cnt >= CNT_MAX[W-1:0]) begin
            clean <= noisy;              // held long enough - accept
            cnt   <= {W{1'b0}};
        end else begin
            cnt   <= cnt + 1'b1;         // candidate change - keep counting
        end
    end

    always @(posedge clk) begin
        if (rst) clean_d <= 1'b0;
        else     clean_d <= clean;
    end

    assign rise = clean & ~clean_d;

endmodule
