module pos_edge_det ( input logic sig,            // Input signal for which positive edge has to be detected
                      input logic clk,            // Input signal for clock
                      output logic pe);           // Output signal that gives a pulse when a positive edge occurs
 
    logic sig_sync0, sig_sync1;
    logic sig_dly;
    
    // 2-FF synchronizer
    always_ff @(posedge clk) begin
        sig_sync0 <= sig;
        sig_sync1 <= sig_sync0;
    end
    
    // Edge detector
    always_ff @(posedge clk) begin
        sig_dly <= sig_sync1;
        pe <= sig_sync1 & ~sig_dly;
    end    
endmodule 