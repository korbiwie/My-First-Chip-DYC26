module sandpile_renderer #(
    parameter MAX_SIZE = 32,
    parameter SCREEN_WIDTH = 640,
    parameter SCREEN_HEIGHT = 480
)(
    input  logic      clk,
    input  logic [9:0] pixel_x,
    input  logic [9:0] pixel_y,
    input  logic [8:0] grid_size,
    input  logic [2:0] grid_data,
    output logic [$clog2(MAX_SIZE)-1:0] grid_addr_x,
    output logic [$clog2(MAX_SIZE)-1:0] grid_addr_y,
    output logic [11:0] color 
);

    localparam [15:0] grid_pixel_width = 480;
    localparam [15:0] offset_x = 16'd80;
    localparam [15:0] offset_y = 16'd0;

    logic        in_bounds_reg;
    logic [15:0] next_index_x, next_index_y;
    logic        next_in_bounds;
    logic [9:0]  rel_x, rel_y;
    logic [27:0] c, r;

    logic in_bounds_vga_sync;

    always_comb begin
        next_index_x = 0;
        next_index_y = 0;
        rel_x = 0;
        rel_y = 0;
        c = 0;
        r = 0;
        next_in_bounds = 1'b0;

        if (16'(pixel_x) >= offset_x && 16'(pixel_x) < (offset_x + grid_pixel_width) &&
            16'(pixel_y) < 480) begin

            rel_x = 10'(pixel_x - offset_x);
            rel_y = 10'(pixel_y);   

            if (grid_size > 0) begin
                c = (28'(rel_x) * 28'(grid_size)) / 28'd480;
                r = (28'(rel_y) * 28'(grid_size)) / 28'd480;

                if (c < MAX_SIZE && r < MAX_SIZE) begin
                    next_index_x = 16'(c);
                    next_index_y = 16'(r);
                    next_in_bounds = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        grid_addr_x   <= next_index_x[$clog2(MAX_SIZE)-1:0];
        grid_addr_y   <= next_index_y[$clog2(MAX_SIZE)-1:0];
        in_bounds_reg <= next_in_bounds;
    end

    always_ff @(posedge clk) begin
        in_bounds_vga_sync <= in_bounds_reg;
        if (!in_bounds_vga_sync) begin
            color <= 12'hFFF; 
        end else begin
            case (grid_data)
                4'd0:    color <= 12'h000; 
                4'd1:    color <= 12'hFDB; 
                4'd2:    color <= 12'hFF0; 
                4'd3:    color <= 12'h842; 
                4'd4:    color <= 12'hF00;
                4'd5:    color <= 12'hF00;
                4'd6:    color <= 12'hF00;
                4'd7:    color <= 12'hF00; 
                default: color <= 12'hFFF; 
            endcase 
        end
    end
endmodule 