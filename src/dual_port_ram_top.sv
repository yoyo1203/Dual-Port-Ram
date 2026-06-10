module dual_port_ram_top #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8,
    parameter MEM_DEPTH  = 256
)(
    input  logic                       clk,
    input  logic                       rst_n,

    // Port A Interface (Multiplexed)
    inout  wire  [DATA_WIDTH-1:0]      porta_ad,
    input  logic                       porta_ale_n,    // Address Latch Enable (active low)
    input  logic                       porta_rd_n,     // Read Enable (active low)
    input  logic                       porta_wr_n,     // Write Enable (active low)
    input  logic                       porta_cs_n,     // Chip Select (active low)

    // Port B Interface (Multiplexed)
    inout  wire  [DATA_WIDTH-1:0]      portb_ad,
    input  logic                       portb_ale_n,
    input  logic                       portb_rd_n,
    input  logic                       portb_wr_n,
    input  logic                       portb_cs_n,

    // Arbitration Interface
    output logic                       arb_grant_a,
    output logic                       arb_grant_b,
    output logic                       collision_detect,

    // Power Management
    input  logic                       sleep_mode,
    input  logic                       retention_mode
);

    // Internal signals
    logic [ADDR_WIDTH-1:0] addr_a_q, addr_b_q;
    logic [DATA_WIDTH-1:0] data_a_in, data_b_in;
    logic [DATA_WIDTH-1:0] data_a_out, data_b_out;
    logic porta_oe, portb_oe;
    logic porta_dir, portb_dir; // 1=output, 0=input

    // Memory array
    logic [DATA_WIDTH-1:0] mem_array [0:MEM_DEPTH-1];

    // Arbitration signals
    logic mem_access_a, mem_access_b;
    logic simultaneous_access;
    logic write_collision;
    logic same_addr_collision;

    // Clock gating signals
    logic clk_gated;
    logic clk_enable;

    // ============================================
    // CLOCK GATING FOR POWER OPTIMIZATION
    // ============================================
    clock_gating u_clock_gating (
        .clk_in      (clk),
        .clk_en      (clk_enable),
        .sleep       (sleep_mode),
        .clk_out     (clk_gated)
    );

    assign clk_enable = ~(porta_cs_n && portb_cs_n) || ~sleep_mode;

    // ============================================
    // ADDRESS LATCHING LOGIC
    // ============================================
    always_ff @(posedge clk_gated or negedge rst_n) begin
        if (!rst_n) begin
            addr_a_q <= '0;
            addr_b_q <= '0;
        end else begin
            // Port A address latch
            if (!porta_cs_n && !porta_ale_n) begin
                addr_a_q <= porta_ad;
            end

            // Port B address latch
            if (!portb_cs_n && !portb_ale_n) begin
                addr_b_q <= portb_ad;
            end
        end
    end

    // ============================================
    // ARBITRATION LOGIC
    // ============================================
    always_comb begin
        simultaneous_access = (!porta_cs_n && !portb_cs_n) &&
                             ((!porta_rd_n || !porta_wr_n) &&
                              (!portb_rd_n || !portb_wr_n));

        same_addr_collision = simultaneous_access && (addr_a_q == addr_b_q);
        write_collision = same_addr_collision && (!porta_wr_n && !portb_wr_n);

        // Priority-based arbitration (Port A has higher priority)
        if (simultaneous_access) begin
            arb_grant_a = 1'b1;
            arb_grant_b = 1'b0;
        end else begin
            arb_grant_a = !porta_cs_n;
            arb_grant_b = !portb_cs_n;
        end
    end

    assign collision_detect = write_collision;

    // ============================================
    // MEMORY ACCESS CONTROL
    // ============================================
    always_ff @(posedge clk_gated or negedge rst_n) begin
        if (!rst_n) begin
            data_a_out <= '0;
            data_b_out <= '0;
            mem_access_a <= 1'b0;
            mem_access_b <= 1'b0;
            // Initialize memory once from this single sequential process
            if (retention_mode) begin
                for (int i = 0; i < MEM_DEPTH; i++) begin
                    mem_array[i] <= '1;
                end
            end else begin
                for (int i = 0; i < MEM_DEPTH; i++) begin
                    mem_array[i] <= '0;
                end
            end
        end else begin
            // Registered copies for debug/waves only — do not gate operations on these (one-cycle late).
            mem_access_a <= arb_grant_a && !porta_cs_n;
            mem_access_b <= arb_grant_b && !portb_cs_n;

            // Port A: qualify with *current* cycle (same edge as addr/update), not registered mem_access_*.
            if (arb_grant_a && !porta_cs_n) begin
                if (!porta_wr_n && !write_collision) begin
                    mem_array[addr_a_q] <= data_a_in;
                end else if (!porta_rd_n) begin
                    data_a_out <= mem_array[addr_a_q];
                end
            end

            // Port B
            if (arb_grant_b && !portb_cs_n) begin
                if (!portb_wr_n && !write_collision) begin
                    mem_array[addr_b_q] <= data_b_in;
                end else if (!portb_rd_n) begin
                    data_b_out <= mem_array[addr_b_q];
                end
            end
        end
    end

    // ============================================
    // BIDIRECTIONAL PORT CONTROL
    // ============================================
    always_comb begin
        // Port A direction control
        porta_dir = (!porta_cs_n && !porta_rd_n && arb_grant_a);
        porta_oe  = porta_dir;

        // Port B direction control
        portb_dir = (!portb_cs_n && !portb_rd_n && arb_grant_b);
        portb_oe  = portb_dir;

        // Capture input data
        if (!porta_dir) data_a_in = porta_ad;
        if (!portb_dir) data_b_in = portb_ad;
    end

    // Tri-state buffers
    assign porta_ad = porta_oe ? data_a_out : 'z;
    assign portb_ad = portb_oe ? data_b_out : 'z;

endmodule

