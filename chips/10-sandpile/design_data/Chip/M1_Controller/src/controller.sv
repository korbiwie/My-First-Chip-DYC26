module controller(
    input clk,
    input rst_n,
    input start,
    input reset_software,
    input [8:0] grid_size,
    input [11:0] speed,

    output reset_n,
    output game_active_o,
    output [8:0] resolution_o,
    output [11:0] speed_o
);

    enum {RESET, STOPPED, GAMING} state, next_state;

    logic game_active;
    logic [8:0] resolution;

    always_comb begin : control_logic

        next_state = state;
        game_active = 1'b0;

        case (state)
            RESET: begin
                game_active = 1'd0;
                if (start) begin
                    next_state = GAMING;
                end
            end
            STOPPED: begin
                game_active = 1'd0;
                if (start) begin
                    next_state = GAMING;
                end
                if (reset_software) begin
                    next_state = RESET;
                end
            end
            GAMING: begin
                game_active = 1'd1;
                if (~start) begin
                    next_state = STOPPED;
                end
                if (reset_software) begin
                    next_state = RESET;
                end
            end
            default: begin
                next_state = RESET;
                game_active = 1'd0;
            end    
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= RESET;
        end else begin
            state <= next_state;
            if (state != GAMING) begin
                resolution <= grid_size;
            end
        end
    end

    assign reset_n = ~(reset_software || ~rst_n);
    assign game_active_o = game_active;
    assign resolution_o = resolution;
    assign speed_o = speed;

endmodule