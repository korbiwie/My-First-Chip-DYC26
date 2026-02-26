module trng #(
    parameter MAX = 480 // needs to be <= 512
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [9:0]  sensordata,
    input logic [8:0]  resolution,
    output logic [9:0]  random_out
);
    localparam MAX_W = $clog2(MAX);

    logic [24:0] state;
    logic [24+MAX_W:0] product;

    function automatic logic [24:0] keccak_round(input logic [24:0] s);
        logic [24:0] theta, pi, chi;
        for (int i = 0; i < 25; i++) 
            theta[i] = s[i] ^ s[(i+5)%25] ^ s[(i+20)%25];
        for (int i = 0; i < 25; i++) 
            pi[(i*7)%25] = theta[i];
        for (int i = 0; i < 25; i++) 
            chi[i] = pi[i] ^ ((~pi[(i+1)%25]) & pi[(i+2)%25]);

        return chi;    
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= 25'h1234567;
        end else begin
            state <= keccak_round(state ^ {15'b0, sensordata});
            product <= state * resolution;
        end
    end

    assign random_out = product >> 25;  // random_out = (state * MAX) >> 32, so random_out = [0,MAX[
endmodule