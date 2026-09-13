// ---------------------------------------------------------------------------
// reset_sync : asynchronous assert, synchronous de-assert.
//
// KEY0 is a bouncing mechanical button. Releasing it de-asserts reset at a
// random point in the clock period; different flops around the die can then
// leave reset on DIFFERENT clock edges, so the design starts in an
// inconsistent state. Asserting asynchronously (fast, works even with no
// clock) but releasing synchronously fixes that: every flop leaves reset on
// the same edge.
// ---------------------------------------------------------------------------
module reset_sync (
    input  wire clk,
    input  wire async_rst_n,   // KEY0, active low
    output wire rst            // synchronous, active high
);

    (* preserve *) reg [1:0] sync;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) sync <= 2'b00;
        else              sync <= {sync[0], 1'b1};
    end

    assign rst = ~sync[1];

endmodule
