module clock_divider #(
    parameter integer INPUT_FREQ = 25_000_000 // 25 MHz
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [11:0] target_x_hz,
   
    output logic       sim_ce
);
 

    // Simulation Clock
    localparam bit [63:0] SCALE = (2**32) / INPUT_FREQ;
    
    logic [31:0] acc;
    logic [31:0] step;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            acc  <= 32'd0;
            step <= 32'd0;
            sim_ce <= 1'b0;
        end else begin
            step <= target_x_hz * SCALE[31:0];
            // Pulse x_ce high for one cycle when accumulator overflows
            {sim_ce, acc} <= acc + step;
        end
    end

endmodule