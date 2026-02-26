module sand_cell(
    input clk,
    input rst_n,
    input activated_i,

    input drop_i,
    input left_i,
    input right_i,
    input up_i,
    input down_i,
    input [1:0] stack_i,

    output logic collapse_o,
    output [2:0] stack_o
);

    logic [3:0] current_stack;
    logic [3:0] next_stack;

    always_comb begin
        next_stack = {2'd0, stack_i}     //make result 4 bits (size next_stack)
                    + {3'd0, drop_i}     //3#d0 removes warning as 4-Bit adder
                    + {3'd0, left_i}     
                    + {3'd0, right_i} 
                    + {3'd0, up_i} 
                    + {3'd0, down_i};
    end

    always_ff @(posedge clk) begin
        if(!rst_n) begin
            current_stack <= 4'd0;
            collapse_o <= 0;
        end else if (!activated_i) begin
            current_stack <= 4'd0;
            collapse_o <= 0;
        end else begin
            if (next_stack >= 4) begin
                current_stack <= next_stack - 4;
                collapse_o <= 1;
            end else begin
                current_stack <= next_stack;
                collapse_o <= 0;
            end
        end
    end

    assign stack_o = {collapse_o, current_stack[1:0]};

endmodule