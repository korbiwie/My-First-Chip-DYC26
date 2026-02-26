module spi_controller(
    input clk,
    input rst_n,
    input [3:0] spi_address,
    input [11:0] spi_data,
    input is_ready,

    output logic start_o,
    output logic reset_software_o,
    output [8:0] grid_size_o,
    output drop_mode_o,
    output [11:0] speed_o,
    output [9:0] random_seed_o
);

    logic [8:0] grid_size;
    logic drop_mode;
    logic [11:0] speed;

    logic [9:0] random_seed;

    always_ff @(posedge clk) begin
        reset_software_o <= 1'd0;
        if (!rst_n) begin
            grid_size        <= 9'd8;
            drop_mode        <= 1'd0;
            speed            <= 12'd50;
            reset_software_o <= 1'b0;
            start_o          <= 1'b0;
            random_seed      <= 10'd0;
        end else begin
            if (is_ready) begin: read_spi
                case (spi_address)
                    1: begin                    // control
                        start_o <= spi_data[0]; // start   
                        if (spi_data[1]) begin  // reset
                            grid_size        <= 8'd8;
                            drop_mode        <= 1'd0;
                            speed            <= 8'd50;
                            reset_software_o <= 1'b1;
                            start_o          <= 1'b0;
                            random_seed      <= 10'd0;
                        end
                    end
                    // 10: ;                            // chip_id
                    // 11: ;                            // topple_threshold
                    12: grid_size <= spi_data[8:0];     // grid_size
                    13: drop_mode <= spi_data[0];       // drop_mode
                    14: speed <= spi_data[11:0];        // speed
                    15: random_seed <= spi_data[9:0];   // random_seed
                    default: ;                          // Catch-all for anything else
                endcase
            end
        end
    end

    assign grid_size_o   = grid_size;
    assign drop_mode_o   = drop_mode;
    assign speed_o       = speed;
    
    assign random_seed_o = random_seed;

endmodule