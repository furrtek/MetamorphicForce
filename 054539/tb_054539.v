module tb_054539(
);

wire [15:0] AUDIO_OUT_L;
wire [15:0] AUDIO_OUT_R;
wire [23:0] SAMPLE_ROM_ADDR;
reg [7:0] SAMPLE_ROM_DATA;
reg RESET;
reg CLK;
reg [9:0] CPU_ADDR;
reg [7:0] CPU_DATA;
reg CPU_WR;
reg CPU_RD;

top_054539 DUT(
	RESET, CLK,
	CPU_ADDR, CPU_DATA, CPU_WR, CPU_RD,
	SAMPLE_ROM_ADDR, SAMPLE_ROM_DATA,
	AUDIO_OUT_L, AUDIO_OUT_R
);

initial begin
	CLK <= 0;
	CPU_WR <= 0;
	CPU_RD <= 0;
	CPU_ADDR <= 10'h000;
	CPU_DATA <= 8'h00;
	SAMPLE_ROM_DATA <= 8'h00;
	RESET <= 1;
	#10
	RESET <= 0;
	#10
	CPU_ADDR <= 10'h22F;
	CPU_DATA <= 8'b00000001;	// Enable PCM
	CPU_WR <= 1;
	#2
	// Set up channel 0
	CPU_ADDR <= 10'h000;
	CPU_DATA <= 8'h15;	// Pitch LSB
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h001;
	CPU_DATA <= 8'h00;	// Pitch MID
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h002;
	CPU_DATA <= 8'h00;	// Pitch MSB
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h003;
	CPU_DATA <= 8'h30;	// Volume
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h004;
	CPU_DATA <= 8'h10;	// Reverb volume
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h006;
	CPU_DATA <= 8'h23;	// Reverb delay LSB
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h007;
	CPU_DATA <= 8'h01;	// Reverb delay MSB
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h008;
	CPU_DATA <= 8'h00;	// Loop start LSB
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h009;
	CPU_DATA <= 8'h10;	// Loop start MID
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h00A;
	CPU_DATA <= 8'h00;	// Loop start MSB
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h00C;
	CPU_DATA <= 8'h2A;	// Start LSB
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h00D;
	CPU_DATA <= 8'h00;	// Start MID
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h00E;
	CPU_DATA <= 8'h00;	// Start MSB
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h200;
	CPU_DATA <= 8'h00;	// Type
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h201;
	CPU_DATA <= 8'h00;	// Loop flag
	CPU_WR <= 1;
	#2
	CPU_ADDR <= 10'h214;
	CPU_DATA <= 8'b00000001;	// Key on for CH0
	CPU_WR <= 1;
	#2
	CPU_WR <= 0;
end

always
	#1 CLK <= ~CLK;

endmodule
