module top_vga_sandpile #(
    parameter MAX_SIZE = 32
)
(
    input  logic       clk,    
    input  logic       rst_n,
    input  logic [8:0] resolution,
    input        [2:0] grid_data,
    output logic [$clog2(MAX_SIZE)-1:0] grid_addr_x,
    output logic [$clog2(MAX_SIZE)-1:0] grid_addr_y,
    output logic [3:0] vga_r,
    output logic [3:0] vga_g,
    output logic [3:0] vga_b,
    output logic       vga_hs, 
    output logic       vga_vs  
);


    logic [9:0] x, y;
    logic hsync, vsync, video_on;
    logic [11:0] color; 

    vga_controller vga_unit (
        .clk(clk),
        .reset_n(rst_n),
        .video_on(video_on),
        .hsync(hsync),
        .vsync(vsync),
        .pixel_x(x),
        .pixel_y(y)
    );

    sandpile_renderer #(.MAX_SIZE(MAX_SIZE)) renderer_unit (
        .clk(clk),
        .pixel_x(x),
        .pixel_y(y),
        .grid_size(resolution),
        .grid_data(grid_data),
        .grid_addr_x(grid_addr_x),
        .grid_addr_y(grid_addr_y),
        .color(color)
    );
    
    assign vga_r = video_on ? color[11:8] : 4'h0; 
    assign vga_g = video_on ? color[7:4] : 4'h0; 
    assign vga_b = video_on ? color[3:0] : 4'h0;

    assign vga_hs = hsync;
    assign vga_vs = vsync;

endmodule