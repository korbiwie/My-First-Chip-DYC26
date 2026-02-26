module chip #(
    parameter ROWS = 32,
    parameter COLS = 32,
    parameter GRID_SIZE = ROWS * COLS,
    parameter ROWS_SMALL = 4,
    parameter COLS_SMALL = 4,
    parameter INPUT_FREQ = 25_000_000
)(
    input clk,
    input rst_n,        // Dein externer Active-Low Reset
    input sclk,
    input pico,
    input cs,
    output logic       poci,
    output logic [3:0] vga_r,
    output logic [3:0] vga_g,
    output logic [3:0] vga_b,
    output logic       vga_hs, 
    output logic       vga_vs
);

    // --- MMCM / Clock Wizard Signale ---
    // logic clk;          // Dein 25 MHz Arbeitstakt vom MMCM
    // logic locked;       // 1 = MMCM ist stabil eingeloggt
    // logic system_rst_n; // Sicherer interner Reset
    // logic clk_unused;   // Dummy für den alten Divider-Ausgang

    // assign system_rst_n = rst_n & locked;

    // clk_wiz_0 u_mmcm (
    //     .clk_in1  (clk_100),    // 100 MHz Eingang
    //     .resetn   (rst_n),      // Dein Taster direkt an den MMCM
    //     .clk_out1 (clk),        // Dein 25 MHz Haupttakt
    //     .locked   (locked)      // Status-Signal
    // );

    logic sim_ce;
    logic [8:0] grid_size, resolution;
    logic drop_mode;
    logic [11:0] speed_spi, speed;
    logic reset_n; // Wird intern vom Controller gesteuert
    logic game_active;
    logic [9:0] sensordata, true_random_number;
    logic [8:0] drop_x, drop_y;
    logic [3:0] spi_address;
    logic [11:0] spi_data;
    logic is_ready, start, reset_software;
    logic [$clog2(ROWS)-1:0] stack_addr_x;
    logic [$clog2(COLS)-1:0] stack_addr_y;
    logic [2:0] stack_data;
    logic [9:0] x, y;
    logic video_on;
    logic [11:0] color; 

    macro_sand_array #(
        .ROWS(ROWS), 
        .COLS(COLS), 
        .ROWS_SMALL(ROWS_SMALL), 
        .COLS_SMALL(COLS_SMALL)
    ) u_macro_sand_array (
        .clk(clk), 
        .rst_n(reset_n), 
        .new_frame_i(sim_ce && game_active),
        .drop_i(1), 
        .drop_x(drop_x), 
        .drop_y(drop_y),
        .stack_addr_x(stack_addr_x), 
        .stack_addr_y(stack_addr_y),
        .stack_data(stack_data), 
        .resolution(resolution)
    );

    spi_module u_spi_module (
        .sys_clock      (clk),
        .rst_n          (rst_n),
        .PICO           (pico),
        .POCI           (poci),
        .SS             (cs),
        .SCLK           (sclk),
        .spi_address    (spi_address),
        .spi_data       (spi_data),
        .spi_is_ready   (is_ready)
    );

    spi_controller u_spi_controller (
        .clk(clk), 
        .rst_n(rst_n), 
        .spi_address(spi_address), 
        .spi_data(spi_data),
        .is_ready(is_ready), 
        .start_o(start), 
        .reset_software_o(reset_software),
        .grid_size_o(grid_size), 
        .drop_mode_o(drop_mode),
        .speed_o(speed_spi), 
        .random_seed_o(sensordata)
    );

    controller u_controller (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(start), 
        .reset_software(reset_software),
        .grid_size(grid_size), 
        .speed(speed_spi), 
        .reset_n(reset_n),
        .game_active_o(game_active), 
        .resolution_o(resolution), 
        .speed_o(speed)
    );

    game_controller #(
        .ROWS(ROWS), 
        .COLS(COLS)) u_game_controller (
        .clk(clk), 
        .rst_n(reset_n),
        .resolution(resolution), 
        .drop_mode(drop_mode), 
        .rng(true_random_number[8:0]), 
        .drop_x(drop_x), 
        .drop_y(drop_y)
    );

    trng #(.MAX(ROWS)) u_trng (
        .clk(clk), 
        .rst_n(reset_n), 
        .sensordata(sensordata),
        .resolution(resolution), 
        .random_out(true_random_number)
    );

    vga_controller u_vga_controller (
        .clk(clk), 
        .reset_n(rst_n), 
        .video_on(video_on), 
        .hsync(vga_hs), 
        .vsync(vga_vs), 
        .pixel_x(x), 
        .pixel_y(y)
    );

    sandpile_renderer #(.MAX_SIZE(ROWS)) renderer_unit (
        .clk(clk), 
        .pixel_x(x), 
        .pixel_y(y), 
        .grid_size(resolution),
        .grid_data(stack_data), 
        .grid_addr_x(stack_addr_x), 
        .grid_addr_y(stack_addr_y), 
        .color(color)
    );

    clock_divider #(
        .INPUT_FREQ(INPUT_FREQ)
    ) u_clock_divider (
        .clk(clk),             // Nutzt den stabilen MMCM-Takt als Basis
        .rst_n(rst_n),
        .target_x_hz(speed),
        .sim_ce(sim_ce)
    );

    assign vga_r = video_on ? color[11:8] : 4'h0; 
    assign vga_g = video_on ? color[7:4] : 4'h0; 
    assign vga_b = video_on ? color[3:0] : 4'h0;

endmodule