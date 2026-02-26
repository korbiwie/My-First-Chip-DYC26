module game_controller #(
    parameter int unsigned ROWS = 32,
    parameter int unsigned COLS = 32
)(
    input clk,
    input rst_n,
    input drop_mode,
    input [8:0] rng,
    input [8:0] resolution,

    output logic [8:0] drop_x,
    output logic [8:0] drop_y
);

    logic write_drop_x;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            drop_x <= 0;
            drop_y <= 0;
            write_drop_x <= 1;
        end else begin
            if (drop_mode) begin
                // drop in center
                drop_x <= resolution >> 1;
                drop_y <= resolution >> 1;
            end else begin
                // drop random
                if (write_drop_x) begin
                    drop_x <= rng;
                end else begin
                    drop_y <= rng;
                end
                write_drop_x <= ~write_drop_x;
            end
        end
    end

endmodule