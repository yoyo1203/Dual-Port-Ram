module clock_gating (
    input  logic clk_in,
    input  logic clk_en,
    input  logic sleep,
    output logic clk_out
);
    // Pass-through for Tiny Tapeout synthesis (custom ICG not required for shuttle)
    assign clk_out = clk_in;

endmodule
