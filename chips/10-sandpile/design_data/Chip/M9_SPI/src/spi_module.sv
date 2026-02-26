module spi_module
	( 
	// System inputs
	input logic sys_clock,
	input logic rst_n,

	// SPI 
	input logic SCLK,
	input logic SS,
	input logic PICO,
	// current not used
	output logic POCI,

	// spi_controller output
	output logic [3:0] spi_address,
    output logic [11:0] spi_data,
    output logic spi_is_ready
	);

    
    logic [7:0] chip_id = 8'h78;
	logic [3:0] bit_counter;
	logic [3:0] bit_counter_send;
	logic [15:0] data_word_recv_reg;
	logic is_poci_ready;
	
	assign spi_address = data_word_recv_reg[15:12];
	assign spi_data = data_word_recv_reg[11:0];
	    	
	logic rising_sclk_edge;
	pos_edge_det spi_edge_pos(
		.sig(SCLK), 
		.clk(sys_clock), 
		.pe(rising_sclk_edge)
	);
	
	always_ff @(posedge sys_clock) begin
		if (!rst_n) begin
			bit_counter <= 4'b0;	
			bit_counter_send <= 4'b0;	
			data_word_recv_reg <= '0;
			spi_is_ready <= 1'b0;	
			POCI <= 1'b0;
			is_poci_ready <= 1'b0;
		end
		else if(SS) begin 
			bit_counter <= 4'b0;
			bit_counter_send <= 4'b0;
			spi_is_ready <= 1'b0;
			POCI <= 1'b0;
			is_poci_ready <= 1'b0;
		end
		else if(rising_sclk_edge) begin
            if(!spi_is_ready) begin 
                data_word_recv_reg[15 - bit_counter] <= PICO;
    
				if(bit_counter == 7) is_poci_ready <= 1'b1;
                if (bit_counter == 15) begin
                    bit_counter <= 4'b0;
                    spi_is_ready <= 1'b1;
                end
                else bit_counter <= bit_counter + 4'b1;
			end 
			// return chip_id as transmission test
			if(is_poci_ready && (spi_address == 4'hA)) begin
				POCI <= chip_id[7 - bit_counter_send];
				if(bit_counter_send < 7) bit_counter_send <= bit_counter_send + 4'b1;
			end
			
		end
	end
endmodule