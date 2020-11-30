module top_video(
	input [1:0] CLOCK_24,
	
	input [9:0] SW,
	input [3:0] KEY,
	
	output [3:0] VGA_R,
	output [3:0] VGA_G,
	output [3:0] VGA_B,
	output VGA_HS,
	output VGA_VS,
	
	output [7:0] LEDG,
	output [9:0] LEDR,
	
	output [6:0] HEX0,
	output [6:0] HEX1,
	output [6:0] HEX2,
	output [6:0] HEX3
);

parameter STATE_INIT = 4'd0;
parameter STATE_RUN = 4'd1;

reg [3:0] STATE;

reg [9:0] VRAM_ADDR;
reg [7:0] VRAM_DIN;
wire [7:0] VRAM_DOUT;
reg VRAM_WE;
	
reg [9:0] HCOUNT;
reg [9:0] VCOUNT;
reg [9:0] ACTIVE_X;
reg [9:0] ACTIVE_Y;

reg [10:0] GFXROM_ADDR;
wire [31:0] GFXROM_DATA;	// 16x 2bpp pixels
reg [31:0] PIXEL_SR;

reg [11:0] PAL_OUT;
reg TILE_PAL, TILE_PAL_PREV;

vga_pll VGA_PLL(CLOCK_24[0], CLK_VGA);

gfxrom GFXROM(GFXROM_ADDR,	CLK_VGA,	GFXROM_DATA);

vram TILEMAP(VRAM_ADDR, CLK_VGA, VRAM_DIN, VRAM_WE, VRAM_DOUT);	// PTTTTTTT P:Palette T:Tile #

assign HEX0 = 7'b0000000;
assign HEX1 = 7'b0000000;
assign HEX2 = 7'b0000000;
assign HEX3 = 7'b0000000;
assign LEDG = 8'b00000000;
assign LEDR = 10'b0000000000;

assign ACTIVE_V = (VCOUNT >= 2) && (VCOUNT < 2+480);
assign ACTIVE = (HCOUNT >= 16) && (HCOUNT < 16+32*16) && ACTIVE_V;
assign VGA_HS = ~((HCOUNT >= 656) && (HCOUNT < 656+96));
assign VGA_VS = ~((VCOUNT >= 490) && (VCOUNT < 490+2));

assign VGA_R = ACTIVE ? PAL_OUT[11:8] : 4'b0000;
assign VGA_G = ACTIVE ? PAL_OUT[7:4] : 4'b0000;
assign VGA_B = ACTIVE ? PAL_OUT[3:0] : 4'b0000;

always @(*) begin
	case({TILE_PAL, PIXEL_SR[31:30]})
		3'b0_00: PAL_OUT <= 12'b0000_0000_0000;
		3'b0_01: PAL_OUT <= 12'b0101_0101_0101;
		3'b0_10: PAL_OUT <= 12'b1010_1010_1010;
		3'b0_11: PAL_OUT <= 12'b1111_1111_1111;
		3'b1_00: PAL_OUT <= 12'b0000_0000_0000;
		3'b1_01: PAL_OUT <= 12'b0011_0010_1000;
		3'b1_10: PAL_OUT <= 12'b0110_0011_1110;
		3'b1_11: PAL_OUT <= 12'b1111_1111_1111;
	endcase
end

assign RESET = ~KEY[0];

always @(posedge CLK_VGA or posedge RESET) begin
	if (RESET) begin
		STATE <= STATE_INIT;
		HCOUNT <= 10'd0;
		VCOUNT <= 10'd0;
	end else begin
		if (STATE == STATE_INIT) begin
			// Use HCOUNT as a counter to init TILEMAP
			VRAM_WE <= 1'b1;
			VRAM_ADDR <= HCOUNT;
			
			if ((!HCOUNT[4:2]) && (!HCOUNT[9:7]))
				// 000xx000xx
				VRAM_DIN <= {1'b0, 3'b000, HCOUNT[6:5], HCOUNT[1:0]};
			else if (HCOUNT[9:6] == 4'b0011)
				// 0011yxxxxx
				VRAM_DIN <= {1'b1, {1'b0, HCOUNT[5:0]} + 7'd16};
			else
				VRAM_DIN <= {1'b0, 7'd79};	// Empty tile
			
			if (HCOUNT == 10'd1023) begin
				STATE <= STATE_RUN;
				VRAM_WE <= 1'b0;
				HCOUNT <= 10'd0;
			end else begin
				HCOUNT <= HCOUNT + 1'b1;
			end
		end else if (STATE == STATE_RUN) begin
			// VGA 640x480 sync
			if (HCOUNT < 10'd799) begin	// 800 Whole line
			
				// Start tilemap rendering process 16 pixels before active output
				// Pixel 0: Set VRAM_ADDR
				// Pixel 2: Set GFXROM_ADDR from VRAM_DOUT
				// Pixel 15: Load GFXROM_DATA in shift register
				// Pixel 16+: Shift
				if ((HCOUNT >= 0) && (HCOUNT < 0+640)) begin
					if (ACTIVE_X[3:0] == 4'd0) begin
						VRAM_ADDR <= {ACTIVE_Y[8:4], ACTIVE_X[8:4]};
					end else if (ACTIVE_X[3:0] == 4'd2) begin
						GFXROM_ADDR <= {VRAM_DOUT[6:0], ACTIVE_Y[3:0]};
						TILE_PAL_PREV <= VRAM_DOUT[7];
					end
					
					if (ACTIVE_X[3:0] == 4'd15) begin
						PIXEL_SR <= GFXROM_DATA;
						TILE_PAL <= TILE_PAL_PREV;
					end else
						PIXEL_SR <= {PIXEL_SR[29:0], 2'b00};
					
					ACTIVE_X <= ACTIVE_X + 1'b1;
				end
				
				HCOUNT <= HCOUNT + 1'b1;
			end else begin
				// New raster line
				HCOUNT <= 0;
				
				ACTIVE_X <= 10'd0;
				
				if (VCOUNT == 524) begin	// 525 Whole frame
					// New frame
					VCOUNT <= 0;
					ACTIVE_Y <= 10'd0;
				end else begin
					if (ACTIVE_V) begin
						ACTIVE_Y <= ACTIVE_Y + 1'b1;
					end
					VCOUNT <= VCOUNT + 1'b1;
				end
			end
		end
	end
end

endmodule
