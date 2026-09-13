// ---------------------------------------------------------------------------
// clk_div : divides CLOCK_50 down to a one-clock-wide 'tick' pulse.
//
// DIV_MAX is a PARAMETER, not a hard-coded constant. With DIV_MAX hard-coded
// at 49_999_999 a testbench must simulate 500,000,000 ns to see a single
// second of behaviour, which makes regression testing impossible. Overriding
// DIV_MAX to a small number in the testbench cuts simulation time by ~7 orders
// of magnitude while exercising identical logic.
//
// NOTE: this produces an enable PULSE, not a divided clock. The whole design
// stays in one 50 MHz clock domain, so there are no CDC problems, no gated
// clocks, and static timing analysis covers every path.
//
// DIV_MAX = (f_clk / f_tick) - 1     e.g. 50e6/1 - 1 = 49_999_999
// ---------------------------------------------------------------------------
module clk_div #(
    parameter integer DIV_MAX = 49_999_999
)(
    input  wire clk,
    input  wire rst,      // synchronous, active high
    output reg  tick
);

    localparam integer W = (DIV_MAX < 2) ? 1 : $clog2(DIV_MAX + 1);

    reg [W-1:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            cnt  <= {W{1'b0}};
            tick <= 1'b0;
        end else if (cnt >= DIV_MAX[W-1:0]) begin
            cnt  <= {W{1'b0}};
            tick <= 1'b1;
        end else begin
            cnt  <= cnt + 1'b1;
            tick <= 1'b0;
        end
    end

endmodule
