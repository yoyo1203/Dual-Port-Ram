module clock_gating (
    input  logic clk_in,
    input  logic clk_en,
    input  logic sleep,
    output logic clk_out
);
    // Negedge capture approximates ICG latch+VCS (no always_latch + init ICPD_INIT).
    // `bit` defaults to 0 — no second driver vs always_*.
    bit latch_q;

    always_ff @(negedge clk_in) begin
        latch_q <= clk_en && !sleep;
    end

    assign clk_out = clk_in && latch_q;

endmodule
