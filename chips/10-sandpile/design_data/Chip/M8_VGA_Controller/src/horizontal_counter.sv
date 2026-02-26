module horizontal_counter (
    input  logic       clk,      
    input  logic       reset_n,  
    output logic [9:0] pixel_x,  
    output logic       done_x    
);

    // Interner Zähler
    logic [9:0] count_reg;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            count_reg <= 10'd0;
        end else begin
            if (done_x) begin
                count_reg <= 10'd0; 
            end else begin
                count_reg <= count_reg + 10'd1; 
            end
        end
    end

    assign done_x = (count_reg == 10'd799);
    
    assign pixel_x = count_reg;

endmodule