// ---------------------------------------------------------------------------
// sync_2ff : two flip-flop synchroniser for an asynchronous input.
//
// Mechanical push-buttons are asynchronous to CLOCK_50. Sampling them directly
// into logic risks metastability: a flop whose setup/hold window is violated
// can sit between levels for an unbounded time, and if that output fans out to
// several loads they may resolve to DIFFERENT values, corrupting FSM state.
// Two flops in series give the first one a full clock period to settle.
// ---------------------------------------------------------------------------
module sync_2ff (
    input  wire clk,
    input  wire rst,     // synchronous, active high
    input  wire d,       // asynchronous input
    output wire q        // synchronised to clk
);

    // 'preserve' stops Quartus merging/retiming these flops away, which would
    // defeat the purpose. Keep both flops physically close in the fitter.
    (* preserve *) reg [1:0] sync;

    always @(posedge clk) begin
        if (rst) sync <= 2'b00;
        else     sync <= {sync[0], d};
    end

    assign q = sync[1];

endmodule
