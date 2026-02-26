module vga_controller (
    input  logic       clk,      
    input  logic       reset_n,  
    output logic       video_on, 
    output logic       hsync,    
    output logic       vsync,    
    output logic [9:0] pixel_x,  
    output logic [9:0] pixel_y   
);

    logic done_x;

    logic hsync_raw, vsync_raw, video_on_raw;
    logic [3:0] hsync_pipe, vsync_pipe, video_on_pipe;

    localparam int H_DISPLAY     = 640;
    localparam int H_FRONT_PORCH = 16;
    localparam int H_RETRACE     = 96;
    localparam int H_BACK_PORCH  = 48;

    localparam int V_DISPLAY     = 480;
    localparam int V_FRONT_PORCH = 10;
    localparam int V_RETRACE     = 2;
    localparam int V_BACK_PORCH  = 33;


    horizontal_counter u1 (
        .clk     (clk),
        .reset_n (reset_n),
        .done_x  (done_x),
        .pixel_x (pixel_x)
    );

    vertical_counter u2 (
        .clk     (clk),
        .reset_n (reset_n),
        .enable  (done_x),
        .pixel_y (pixel_y)    
    );
    
    assign hsync_raw = ~(int'(pixel_x) >= (H_DISPLAY + H_FRONT_PORCH) && 
                         int'(pixel_x) <  (H_DISPLAY + H_FRONT_PORCH + H_RETRACE));

    assign vsync_raw = ~(int'(pixel_y) >= (V_DISPLAY + V_FRONT_PORCH) && 
                         int'(pixel_y) <  (V_DISPLAY + V_FRONT_PORCH + V_RETRACE));

    assign video_on_raw = (int'(pixel_x) < H_DISPLAY) && (int'(pixel_y) < V_DISPLAY);

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            hsync_pipe    <= 4'b1111; 
            vsync_pipe    <= 4'b1111;
            video_on_pipe <= 4'b0000;
        end else begin
            hsync_pipe    <= {hsync_pipe[2:0],    hsync_raw};
            vsync_pipe    <= {vsync_pipe[2:0],    vsync_raw};
            video_on_pipe <= {video_on_pipe[2:0], video_on_raw};
        end
    end


    assign hsync    = hsync_pipe[3];
    assign vsync    = vsync_pipe[3];
    assign video_on = video_on_pipe[3];
    
endmodule