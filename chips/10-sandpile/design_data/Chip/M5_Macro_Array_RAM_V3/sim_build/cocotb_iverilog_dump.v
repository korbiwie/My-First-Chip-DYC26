module cocotb_iverilog_dump();
initial begin
    string dumpfile_path;    if ($value$plusargs("dumpfile_path=%s", dumpfile_path)) begin
        $dumpfile(dumpfile_path);
    end else begin
        $dumpfile("/workspaces/My-First-Chip-DYC26/chips/10-sandpile/design_data/Chip/M5_Macro_Array_RAM_V3/sim_build/macro_sand_array.fst");
    end
    $dumpvars(0, macro_sand_array);
end
endmodule
