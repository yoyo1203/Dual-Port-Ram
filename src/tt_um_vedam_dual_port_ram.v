`default_nettype none

module tt_um_vedam_dual_port_ram (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire       port_sel       = ui_in[0];
    wire       ale_n          = ui_in[1];
    wire       rd_n           = ui_in[2];
    wire       wr_n           = ui_in[3];
    wire       cs_n           = ui_in[4];
    wire       sleep_mode     = ui_in[5];
    wire       retention_mode = ui_in[6];

    wire       porta_cs_n   = port_sel ? 1'b1 : cs_n;
    wire       portb_cs_n   = port_sel ? cs_n : 1'b1;
    wire       porta_ale_n  = port_sel ? 1'b1 : ale_n;
    wire       portb_ale_n  = port_sel ? ale_n : 1'b1;
    wire       porta_rd_n   = port_sel ? 1'b1 : rd_n;
    wire       portb_rd_n   = port_sel ? rd_n : 1'b1;
    wire       porta_wr_n   = port_sel ? 1'b1 : wr_n;
    wire       portb_wr_n   = port_sel ? wr_n : 1'b1;

    wire       grant_a;
    wire       grant_b;
    wire       collision;

    wire [7:0] porta_ad;
    wire [7:0] portb_ad;

    // 16x8 for 1x2 tile — 256x8 is too large for Tiny Tapeout
    dual_port_ram_top #(
        .ADDR_WIDTH (4),
        .MEM_DEPTH  (16)
    ) u_ram (
        .clk             (clk),
        .rst_n           (rst_n),
        .porta_ad        (porta_ad),
        .porta_ale_n     (porta_ale_n),
        .porta_rd_n      (porta_rd_n),
        .porta_wr_n      (porta_wr_n),
        .porta_cs_n      (porta_cs_n),
        .portb_ad        (portb_ad),
        .portb_ale_n     (portb_ale_n),
        .portb_rd_n      (portb_rd_n),
        .portb_wr_n      (portb_wr_n),
        .portb_cs_n      (portb_cs_n),
        .arb_grant_a     (grant_a),
        .arb_grant_b     (grant_b),
        .collision_detect(collision),
        .sleep_mode      (sleep_mode),
        .retention_mode  (retention_mode)
    );

    wire bus_active_a = ~port_sel & ~porta_cs_n;
    wire bus_active_b =  port_sel & ~portb_cs_n;
    wire bus_read_a   = bus_active_a & ~porta_rd_n;
    wire bus_read_b   = bus_active_b & ~portb_rd_n;
    wire drive_in_a   = bus_active_a & porta_rd_n;
    wire drive_in_b   = bus_active_b & portb_rd_n;

    assign porta_ad = drive_in_a ? uio_in : 8'bz;
    assign portb_ad = drive_in_b ? uio_in : 8'bz;

    assign uio_out = bus_read_a ? porta_ad : bus_read_b ? portb_ad : 8'b0;
    assign uio_oe  = {8{(bus_read_a | bus_read_b)}};

    assign uo_out[0]   = collision;
    assign uo_out[1]   = grant_a;
    assign uo_out[2]   = grant_b;
    assign uo_out[7:3] = 5'b0;

    wire _unused = ena;

endmodule
