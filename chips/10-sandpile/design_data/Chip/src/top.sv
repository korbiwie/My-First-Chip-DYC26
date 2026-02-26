module top(
    `ifdef USE_POWER_PINS
    inout wire IOVDD,
    inout wire IOVSS,
    inout wire VDD,
    inout wire VSS,
    `endif

    inout clk_PAD,
    inout rst_n_PAD,

    // SPI inputs
    inout sclk_PAD,
    inout cs_PAD,
    inout pico_PAD,

    output       poci_PAD,
    // VGA outputs
    output [3:0] vga_r_PADs,
    output [3:0] vga_g_PADs,
    output [3:0] vga_b_PADs,
    output       vga_hs_PAD,
    output       vga_vs_PAD
);

logic clk;
logic rst_n;
logic sclk;
logic cs;
logic pico;
logic poci;
logic [3:0] vga_r;
logic [3:0] vga_g;
logic [3:0] vga_b;
logic vga_hs;
logic vga_vs;

// Power/ground pad instances
generate
for (genvar i=0; i<1; i++) begin : iovdd_pads
    (* keep *)
    sg13g2_IOPadIOVdd iovdd_pad  (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS)
        `endif
    );
end
for (genvar i=0; i<1; i++) begin : iovss_pads
    (* keep *)
    sg13g2_IOPadIOVss iovss_pad  (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS)
        `endif
    );
end
for (genvar i=0; i<1; i++) begin : vdd_pads
    (* keep *)
    sg13g2_IOPadVdd vdd_pad  (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS)
        `endif
    );
end
for (genvar i=0; i<1; i++) begin : vss_pads
    (* keep *)
    sg13g2_IOPadVss vss_pad  (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS)
        `endif
    );
end
endgenerate
// clk PAD instance
sg13g2_IOPadIn clk_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .p2c    (clk),
    .pad    (clk_PAD)
);
//reset PAD instance
sg13g2_IOPadIn rst_n_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .p2c    (rst_n),
    .pad    (rst_n_PAD)
);

// SPI input PADs
sg13g2_IOPadIn sclk_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .p2c    (sclk),
    .pad    (sclk_PAD)
);

sg13g2_IOPadIn cs_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .p2c    (cs),
    .pad    (cs_PAD)
);

sg13g2_IOPadIn pico_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .p2c    (pico),
    .pad    (pico_PAD)
);


sg13g2_IOPadOut30mA poci_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .c2p    (poci),
    .pad    (poci_PAD)
);

//VGA output PADs
generate
for (genvar i=0; i<4; i++) begin : vga_r_pads
    (* keep *)
    sg13g2_IOPadOut30mA vga_r_pad (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS),
        `endif
        .c2p    (vga_r[i]),
        .pad    (vga_r_PADs[i])
    );
end
endgenerate

generate
for (genvar i=0; i<4; i++) begin : vga_g_pads
    (* keep *)
    sg13g2_IOPadOut30mA vga_g_pad (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS),
        `endif
        .c2p    (vga_g[i]),
        .pad    (vga_g_PADs[i])
    );
end
endgenerate

generate
for (genvar i=0; i<4; i++) begin : vga_b_pads
    (* keep *)
    sg13g2_IOPadOut30mA vga_b_pad (
        `ifdef USE_POWER_PINS
        .iovdd  (IOVDD),
        .iovss  (IOVSS),
        .vdd    (VDD),
        .vss    (VSS),
        `endif
        .c2p    (vga_b[i]),
        .pad    (vga_b_PADs[i])
    );
end
endgenerate

sg13g2_IOPadOut30mA vga_hs_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .c2p    (vga_hs),
    .pad    (vga_hs_PAD)
);

sg13g2_IOPadOut30mA vga_vs_pad (
    `ifdef USE_POWER_PINS
    .iovdd  (IOVDD),
    .iovss  (IOVSS),
    .vdd    (VDD),
    .vss    (VSS),
    `endif
    .c2p    (vga_vs),
    .pad    (vga_vs_PAD)
);

chip u_chip (
    .clk(clk),
    .rst_n(rst_n),
    .sclk(sclk),
    .cs(cs),
    .pico(pico),
    .poci(poci),
    .vga_r(vga_r),
    .vga_g(vga_g),
    .vga_b(vga_b),
    .vga_hs(vga_hs),
    .vga_vs(vga_vs)
);

endmodule