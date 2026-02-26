module cocotb_iverilog_dump();
initial begin
    string dumpfile_path;    if ($value$plusargs("dumpfile_path=%s", dumpfile_path)) begin
        $dumpfile(dumpfile_path);
    end else begin
        $dumpfile("/home/korbiwie/hm-ig/2-Semester/hardware-code-design/sandpile/sandpile/M2_SPI_Controller/sim_build/spi_controller.fst");
    end
    $dumpvars(0, spi_controller);
end
endmodule
