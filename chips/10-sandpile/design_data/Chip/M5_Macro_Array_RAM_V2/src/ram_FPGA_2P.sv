module RAM_FPGA_2P #(
    parameter int unsigned DATA_WIDTH = 16,
    parameter int unsigned ADDR_WIDTH = 1024
)(
    input  wire         A_CLK,
    input  wire [9:0]   A_ADDR,
    input  wire [15:0]  A_DIN,
    input  wire [15:0]  A_BM,      // Bit mask (1 = write bit)
    input  wire         A_WEN,     // Active high write enable
    input  wire         A_MEN,     // Memory enable
    input  wire         A_REN,     // Read enable
    output reg  [15:0]  A_DOUT,
    input  wire         A_DLY,     // Ignored on FPGA

    input  wire         B_CLK,
    input  wire [9:0]   B_ADDR,
    input  wire [15:0]  B_DIN,
    input  wire [15:0]  B_BM,
    input  wire         B_WEN,
    input  wire         B_MEN,
    input  wire         B_REN,
    output reg  [15:0]  B_DOUT,
    input  wire         B_DLY      // Ignored on FPGA
);
    // This should infer BRAM on FPGAs
    reg [DATA_WIDTH-1:0] mem [0:ADDR_WIDTH-1];

    always @(posedge A_CLK) begin
        if (A_MEN) begin

            // Write
            if (A_WEN) begin
                for (int i = 0; i < DATA_WIDTH; i++) begin
                    if (A_BM[i])
                        mem[A_ADDR][i] <= A_DIN[i];
                end
            end

            // Read
            if (A_REN)
                A_DOUT <= mem[A_ADDR];
        end
    end

    always @(posedge B_CLK) begin
        if (B_MEN) begin

            if (B_WEN) begin
                for (int i = 0; i < 16; i++) begin
                    if (B_BM[i])
                        mem[B_ADDR][i] <= B_DIN[i];
                end
            end

            if (B_REN)
                B_DOUT <= mem[B_ADDR];
        end
    end

endmodule