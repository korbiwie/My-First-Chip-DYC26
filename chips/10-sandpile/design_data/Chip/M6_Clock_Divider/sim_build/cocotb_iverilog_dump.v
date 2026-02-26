module cocotb_iverilog_dump();
initial begin
    string dumpfile_path;    if ($value$plusargs("dumpfile_path=%s", dumpfile_path)) begin
        $dumpfile(dumpfile_path);
    end else begin
        $dumpfile("/home/korbiwie/hm-ig/2-Semester/hardware-code-design/sandpile/sandpile/Chip/M6_Clock_Divider/sim_build/clock_divider.fst");
    end
    $dumpvars(0, clock_divider);
end
endmodule
