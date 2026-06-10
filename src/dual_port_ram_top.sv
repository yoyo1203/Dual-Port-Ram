module dual_port_ram_top #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8,
    parameter MEM_DEPTH  = 256
)(
    input  logic                       clk,
    input  logic                       rst_n,

    // Port A — separate in/out (no tri-state, synthesis-friendly)
    input  logic [DATA_WIDTH-1:0]      porta_din,
    output logic [DATA_WIDTH-1:0]      porta_dout,
    output logic                       porta_dout_en,
    input  logic                       porta_ale_n,
    input  logic                       porta_rd_n,
    input  logic                       porta_wr_n,
    input  logic                       porta_cs_n,

    // Port B
    input  logic [DATA_WIDTH-1:0]      portb_din,
    output logic [DATA_WIDTH-1:0]      portb_dout,
    output logic                       portb_dout_en,
    input  logic                       portb_ale_n,
    input  logic                       portb_rd_n,
    input  logic                       portb_wr_n,
    input  logic                       portb_cs_n,

    // Arbitration
    output logic                       arb_grant_a,
    output logic                       arb_grant_b,
    output logic                       collision_detect,

    // Power management
    input  logic                       sleep_mode,
    input  logic                       retention_mode
);

    logic [ADDR_WIDTH-1:0] addr_a_q, addr_b_q;
    logic [DATA_WIDTH-1:0] data_a_in, data_b_in;
    logic [DATA_WIDTH-1:0] data_a_out, data_b_out;

    logic [DATA_WIDTH-1:0] mem_array [0:MEM_DEPTH-1];

    logic simultaneous_access;
    logic write_collision;
    logic same_addr_collision;

    logic clk_gated;
    logic clk_enable;

    assign data_a_in = porta_din;
    assign data_b_in = portb_din;

    wire _unused_retention = retention_mode;

    clock_gating u_clock_gating (
        .clk_in      (clk),
        .clk_en      (clk_enable),
        .sleep       (sleep_mode),
        .clk_out     (clk_gated)
    );

    assign clk_enable = ~(porta_cs_n && portb_cs_n) || ~sleep_mode;

    always_ff @(posedge clk_gated or negedge rst_n) begin
        if (!rst_n) begin
            addr_a_q <= '0;
            addr_b_q <= '0;
        end else begin
            if (!porta_cs_n && !porta_ale_n) begin
                addr_a_q <= porta_din;
            end
            if (!portb_cs_n && !portb_ale_n) begin
                addr_b_q <= portb_din;
            end
        end
    end

    always_comb begin
        simultaneous_access = (!porta_cs_n && !portb_cs_n) &&
                             ((!porta_rd_n || !porta_wr_n) &&
                              (!portb_rd_n || !portb_wr_n));

        same_addr_collision = simultaneous_access && (addr_a_q == addr_b_q);
        write_collision = same_addr_collision && (!porta_wr_n && !portb_wr_n);

        if (simultaneous_access) begin
            arb_grant_a = 1'b1;
            arb_grant_b = 1'b0;
        end else begin
            arb_grant_a = !porta_cs_n;
            arb_grant_b = !portb_cs_n;
        end
    end

    assign collision_detect = write_collision;

    assign porta_dout    = data_a_out;
    assign porta_dout_en = !porta_cs_n && !porta_rd_n && arb_grant_a;
    assign portb_dout    = data_b_out;
    assign portb_dout_en = !portb_cs_n && !portb_rd_n && arb_grant_b;

    // Sync reset only for memory — Yosys requires constant async reset values
    always_ff @(posedge clk_gated) begin
        if (!rst_n) begin
            data_a_out <= '0;
            data_b_out <= '0;
            for (int i = 0; i < MEM_DEPTH; i++) begin
                mem_array[i] <= '0;
            end
        end else begin
            if (arb_grant_a && !porta_cs_n) begin
                if (!porta_wr_n && !write_collision) begin
                    mem_array[addr_a_q] <= data_a_in;
                end else if (!porta_rd_n) begin
                    data_a_out <= mem_array[addr_a_q];
                end
            end

            if (arb_grant_b && !portb_cs_n) begin
                if (!portb_wr_n && !write_collision) begin
                    mem_array[addr_b_q] <= data_b_in;
                end else if (!portb_rd_n) begin
                    data_b_out <= mem_array[addr_b_q];
                end
            end
        end
    end

endmodule
