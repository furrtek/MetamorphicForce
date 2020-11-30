// Konami 054539 PCM sound chip
// Based on MAME's k054539.cpp by Aaron Giles
// Verilog implementation: furrtek 2020

module top_054539(
	input RESET,
	input CLK,
	
	input [9:0] CPU_ADDR,
	input [7:0] CPU_DATA,
	input CPU_WR,
	input CPU_RD,
	
	output reg [23:0] SAMPLE_ROM_ADDR,
	input [7:0] SAMPLE_ROM_DATA,
	
	output reg [15:0] AUDIO_OUT_L,
	output reg [15:0] AUDIO_OUT_R
);

/* Registers:
   00..ff: 32 bytes/channel, 8 channels
     00..02: pitch (lsb, mid, msb)
         03: volume (0=max, 0x40=-36dB)
         04: reverb volume (idem)
     05: pan (1-f right, 10 middle, 11-1f left)
     06..07: reverb delay (0=max, current computation non-trusted)
     08..0a: loop (lsb, mid, msb)
     0c..0e: start (lsb, mid, msb) (and current position ?)
   100.1ff: effects?
     13f: pan of the analog input (1-1f)
   200..20f: 2 bytes/channel, 8 channels
     00: type (b2-3), reverse (b5)
     01: loop (b0)
   214: Key on (b0-7 = channel 0-7)
   215: Key off          ""
   227: Timer frequency
   22c: Channel active? (b0-7 = channel 0-7)
   22d: Data read/write port
   22e: ROM/RAM select (00..7f == ROM banks, 80 = Reverb RAM)
   22f: Global control:
        .......x - Enable PCM
        ......x. - Timer related?
        ...x.... - Enable ROM/RAM readback from 0x22d
        ..x..... - Timer output enable?
        x....... - Disable register RAM updates
*/

// DPCM_TABLE
//	0 * 0x100,     1 * 0x100,   4 * 0x100,   9 * 0x100,  16 * 0x100, 25 * 0x100, 36 * 0x100, 49 * 0x100,
// -64 * 0x100, -49 * 0x100, -36 * 0x100, -25 * 0x100, -16 * 0x100, -9 * 0x100, -4 * 0x100, -1 * 0x100
reg [3:0] DPCM_INDEX;
reg [7:0] DPCM_DATA;
always @(DPCM_INDEX) begin
	case (DPCM_INDEX)
		4'd0: DPCM_DATA <= 8'd0;
		4'd1: DPCM_DATA <= 8'd1;
		4'd2: DPCM_DATA <= 8'd4;
		4'd3: DPCM_DATA <= 8'd9;
		4'd4: DPCM_DATA <= 8'd16;
		4'd5: DPCM_DATA <= 8'd25;
		4'd6: DPCM_DATA <= 8'd36;
		4'd7: DPCM_DATA <= 8'd49;
		4'd8: DPCM_DATA <= -8'd64;
		4'd9: DPCM_DATA <= -8'd49;
		4'd10: DPCM_DATA <= -8'd36;
		4'd11: DPCM_DATA <= -8'd25;
		4'd12: DPCM_DATA <= -8'd16;
		4'd13: DPCM_DATA <= -8'd9;
		4'd14: DPCM_DATA <= -8'd4;
		4'd15: DPCM_DATA <= -8'd1;
	endcase
end

reg [7:0] REVERB_RAM [0:16383];
//reg [7:0] SAMPLE_ROM [0:32767];

reg [12:0] REVERB_RAM_ADDR;
reg [7:0] REVERB_RAM_DATA_IN;
reg [7:0] REVERB_RAM_DATA_OUT;
reg REVERB_RAM_RD;
reg REVERB_RAM_WR;

always @(posedge CLK) begin
	if (REVERB_RAM_WR)
		REVERB_RAM[REVERB_RAM_ADDR] <= REVERB_RAM_DATA_IN;
	else if (REVERB_RAM_RD)
		REVERB_RAM_DATA_OUT <= REVERB_RAM[REVERB_RAM_ADDR];
end

reg [23:0] CH_PITCH [0:7];
reg [7:0] CH_MAIN_VOL [0:7];
reg [7:0] CH_REVERB_VOL [0:7];
reg [7:0] CH_PAN [0:7];
reg [15:0] CH_REVERB_DELAY [0:7];
reg [23:0] CH_LOOP_POS [0:7];
reg [23:0] CH_START_POS [0:7];
reg [7:0] CH_TYPE [0:7];
reg CH_LOOP [0:7];

reg [7:0] REG_KEY_ON;
reg [7:0] REG_TIMER_FREQ;
reg [7:0] REG_CH_ACTIVE;
reg [7:0] REG_MEM_BANK;
reg [7:0] REG_CTRL;

// Internal:
reg [23:0] POSREG_LATCH [0:7];
reg [16:0] MEM_PTR;
reg [7:0] CPU_DATA_RD;
reg [5:0] CYCLE_COUNT;
reg [2:0] CH_N;
reg [31:0] temp_cur_pos;
reg [31:0] temp_cur_pfrac;
reg [12:0] reverb_pos;	// 0000~1FFF words (0000~3FFF bytes)
reg [15:0] lval;
reg [15:0] rval;
reg [23:0] chan_pos [0:7];
reg [15:0] cur_val [0:7];
reg [15:0] cur_pval [0:7];
reg [31:0] cur_pfrac [0:7];
reg [23:0] cur_pos [0:7];
reg [13:0] rdelta;
reg REFETCH;
reg [15:0] REVERB_DATA_TEMP;

// xx xxxxxxxx
// 10 xxx01100
// 01 xxx01101
// 01 xxx01110

always @(posedge CLK or posedge RESET) begin
	if (RESET) begin
		REG_CH_ACTIVE <= 8'h00;
		REG_CTRL <= 8'h00;
		CYCLE_COUNT <= 6'd0;
		CH_N <= 3'd0;
		reverb_pos <= 13'd0;
		chan_pos[0] <= 24'd0;
	end else begin
		if (CPU_WR) begin
			// Channel registers active only if REG_CTRL bit 0 is set (PCM enabled)
			//if (CPU_ADDR[9:8] == 2'b01) & () begin
			casez({REG_CTRL[0], CPU_ADDR})
				11'b?00_???00000: CH_PITCH[CPU_ADDR[7:5]][7:0] <= CPU_DATA;		// Pitch lsb
				11'b?00_???00001: CH_PITCH[CPU_ADDR[7:5]][15:8] <= CPU_DATA;		// Pitch mid
				11'b?00_???00010: CH_PITCH[CPU_ADDR[7:5]][23:16] <= CPU_DATA;		// Pitch msb
				
				11'b?00_???00011: CH_MAIN_VOL[CPU_ADDR[7:5]] <= CPU_DATA;		// Vol
				11'b?00_???00100: CH_REVERB_VOL[CPU_ADDR[7:5]] <= CPU_DATA;		// Reverb
				11'b?00_???00101: CH_PAN[CPU_ADDR[7:5]] <= CPU_DATA;		// Pan
				
				11'b?00_???00110: CH_REVERB_DELAY[CPU_ADDR[7:5]][7:0] <= CPU_DATA;		// Reverb delay lsb
				11'b?00_???00111: CH_REVERB_DELAY[CPU_ADDR[7:5]][15:8] <= CPU_DATA;		// Reverb delay msb
				
				11'b?00_???01000: CH_LOOP_POS[CPU_ADDR[7:5]][7:0] <= CPU_DATA;		// Loop lsb
				11'b?00_???01001: CH_LOOP_POS[CPU_ADDR[7:5]][15:8] <= CPU_DATA;	// Loop mid
				11'b?00_???01010: CH_LOOP_POS[CPU_ADDR[7:5]][23:16] <= CPU_DATA;	// Loop msb
				
				11'b100_???01100: POSREG_LATCH[CPU_ADDR[7:5]][7:0] <= CPU_DATA;		// Start lsb
				11'b100_???01101: POSREG_LATCH[CPU_ADDR[7:5]][15:8] <= CPU_DATA;		// Start mid
				11'b100_???01110: POSREG_LATCH[CPU_ADDR[7:5]][23:16] <= CPU_DATA;		// Start msb
				
				11'b?10_0000???0: CH_TYPE[CPU_ADDR[7:5]] <= CPU_DATA;		// Type
				11'b?10_0000???1: CH_LOOP[CPU_ADDR[7:5]] <= CPU_DATA[0];	// Loop flag
				
				11'b?10_00010100: begin		// 214 Key on
					REG_KEY_ON <= CPU_DATA;
				end
				
				11'b?10_00010101: begin		// 215 Key off
					// keyoff(ch):
					if (!REG_CTRL[7])
						REG_CH_ACTIVE <= REG_CH_ACTIVE & ~CPU_DATA;
				end
				
				11'b?10_00100111: begin		// 227 Timer frequency
					// TODO: Frequency = ((CPU_DATA + 38) * clock() / 384 / 14400) * 2
				end
				
				11'b?10_00101101: begin		// 22D Memory R/W port
					// TODO: Is this needed ? Only for the startup test ?
					if (REG_MEM_BANK == 8'h80)
						REVERB_RAM[MEM_PTR] <= CPU_DATA;
					MEM_PTR <= (REG_MEM_BANK == 8'h80) ? (MEM_PTR + 1'b1) & 17'h3FFF : (MEM_PTR + 1'b1) & 17'h1FFFF;
				end
				11'b?10_00101110: begin		// 22E ROM/RAM bank select
					// TODO: Is this needed ? Only for the startup test ?
					REG_MEM_BANK <= CPU_DATA;
					MEM_PTR <= 17'h00000;
				end
				
				11'b?10_00101111: begin		// 22F Global control
					REG_CTRL <= CPU_DATA;
				end
				
				// TODO: regs[offset] = data;
			endcase
		end
		
		if (CPU_RD) begin
			casez(CPU_ADDR)
				10'b10_00101101: begin		// 22D Memory R/W port
					// TODO: Is this needed ? Only for the startup test ?
					if (REG_CTRL[4])	// Reading from 22D enabled
						CPU_DATA_RD <= (REG_MEM_BANK == 8'h80) ?
							REVERB_RAM[MEM_PTR & 17'h3FFF] :
							//SAMPLE_ROM[{REG_MEM_BANK[6:0], MEM_PTR}];
							SAMPLE_ROM_DATA;
					else
						CPU_DATA_RD <= 8'h00;
					// Auto-inc on read can be disabled ?
					MEM_PTR <= (REG_MEM_BANK == 8'h80) ? (MEM_PTR + 1'b1) & 17'h3FFF : (MEM_PTR + 1'b1) & 17'h1FFFF;
				end
			endcase
			// TODO: return regs[offset];
		end
		
		// TODO: Sample rate = clock() / 384 (48 clocks per channel)
		
		// CYCLE_COUNT	0123456789...0123456789...0123456789...
		// CH_N			000000000000011111111111112222222222222...
		// Operation	AAAABBBBBBBBB----BBBBBBBBB----BBBBBBBBB....
		// A: REVERB_RAM fetch and clear
		// B: Channel operations
		// -: Idle
		
		if (CYCLE_COUNT == 6'd48-1) begin
			CYCLE_COUNT <= 6'd0;
			CH_N <= CH_N + 1'b1;
			
			// If PCM is disabled, writing to Key on calls keyon(ch) without updating CH_START_POSs
			if (REG_CTRL[0]) begin
				if (REG_KEY_ON[0]) CH_START_POS[0] <= POSREG_LATCH[0];
				if (REG_KEY_ON[1]) CH_START_POS[1] <= POSREG_LATCH[1];
				if (REG_KEY_ON[2]) CH_START_POS[2] <= POSREG_LATCH[2];
				if (REG_KEY_ON[3]) CH_START_POS[3] <= POSREG_LATCH[3];
				if (REG_KEY_ON[4]) CH_START_POS[4] <= POSREG_LATCH[4];
				if (REG_KEY_ON[5]) CH_START_POS[5] <= POSREG_LATCH[5];
				if (REG_KEY_ON[6]) CH_START_POS[6] <= POSREG_LATCH[6];
				if (REG_KEY_ON[7]) CH_START_POS[7] <= POSREG_LATCH[7];
				REG_KEY_ON <= 8'h00;
			end
			// keyon(ch):
			if (!REG_CTRL[7])
				REG_CH_ACTIVE <= REG_CH_ACTIVE | REG_KEY_ON;
		end else begin
			CYCLE_COUNT <= CYCLE_COUNT + 1'b1;
		
			if (!REG_CTRL[0]) begin
				// PCM off, silence please
				AUDIO_OUT_L <= 16'd0;
				AUDIO_OUT_R <= 16'd0;
			end else begin
			
				if (CH_N == 3'd0) begin
					// Load 16bit value from REVERB_RAM once for the whole 8-channel cycle
					case(CYCLE_COUNT)
						6'd0: begin
							REVERB_RAM_ADDR <= {reverb_pos, 1'b0};
							REVERB_RAM_RD <= 1'b1;
							REVERB_RAM_WR <= 1'b0;
						end
						6'd1: begin
							lval[15:8] <= REVERB_RAM_DATA_OUT;
							rval[15:8] <= REVERB_RAM_DATA_OUT;
							REVERB_RAM_ADDR <= {reverb_pos, 1'b1};
						end
						6'd2: begin
							lval[7:0] <= REVERB_RAM_DATA_OUT;
							rval[7:0] <= REVERB_RAM_DATA_OUT;
							REVERB_RAM_RD <= 1'b0;
							REVERB_RAM_WR <= 1'b1;
							REVERB_RAM_DATA_IN <= 8'h00;
						end
						6'd3: begin
							REVERB_RAM_ADDR <= {reverb_pos, 1'b0};
						end
						6'd4: begin
							REVERB_RAM_WR <= 1'b0;
						end
						default:;
					endcase
				end
			
				// TODO: the following must be done for all 8 channels
				if (CH_N == 3'd0) begin
					if (REG_CH_ACTIVE[0]) begin
						// 'delta' is CH_PITCH
						// 'vol' is CH_MAIN_VOL
						// 'bval' is CH_MAIN_VOL + CH_REVERB_VOL capped at 255
						// 'pan' is CH_PAN
						//		if between 81 and 8F inclusive: -= 81 (0~E)
						//		if between 11 and 1F inclusive: -= 11 (0~E)
						//		else: = 7 (center)
						// 'rdelta' is ((CH_REVERB_DELAY >> 3) + reverb_pos) & 0x3FFF
						// 'cur_pos' is CH_START_POS
						//	If reverse playback: delta = -delta, fdelta = 0x10000, pdelta = -1
						//	If normal playback: fdelta = -0x10000, pdelta = 1
						if (CYCLE_COUNT == 6'd3) begin
							rdelta <= (CH_REVERB_DELAY[0][12:3] + reverb_pos);
							cur_pos[0] <= CH_START_POS[0];
						
							// If CH_START was written to by CPU: cur_pfrac = 0, cur_val = 0, cur_pval = 0
							if (chan_pos[0] != CH_START_POS[0]) begin
								chan_pos[0] <= CH_START_POS[0];
								cur_pfrac[0] <= 0;
								$display("cur_pfrac!");
								cur_val[0] <= 0;
								cur_pval[0] <= 0;
							end
						end
						
						case(CH_TYPE[0][3:2])
							2'b00: begin	// 8bit PCM
								if (CYCLE_COUNT == 6'd4) begin
									cur_pfrac[0] <= cur_pfrac[0] + (CH_TYPE[0][5] ? -CH_PITCH[0] : CH_PITCH[0]);	// cur_pfrac += delta;
									// TODO: while(cur_pfrac & FFFF0000) {	// Wtf ?
									if (CH_TYPE[0][5]) begin	//	cur_pos += pdelta, cur_pfrac += fdelta
										cur_pfrac[0] <= cur_pfrac[0] + 32'h10000;
										cur_pos[0] <= cur_pos[0] - 1'b1;
									end else begin
										cur_pfrac[0] <= cur_pfrac[0] - 32'h10000;
										cur_pos[0] <= cur_pos[0] + 1'b1;
									end
									cur_pval[0] <= cur_val[0];	//	cur_pval = cur_val;
									SAMPLE_ROM_ADDR <= cur_pos[0];
									REFETCH <= 1'b0;
								end else if (CYCLE_COUNT == 6'd5) begin
									if (SAMPLE_ROM_DATA == 8'h80) begin
										if (CH_LOOP[0]) begin
											cur_pos[0] <= CH_LOOP_POS[0];
											SAMPLE_ROM_ADDR <= CH_LOOP_POS[0];
											REFETCH <= 1'b1;
										end else begin
											// keyoff(0):
											if (!REG_CTRL[7])
												REG_CH_ACTIVE[0] <= 1'b0;
											cur_val[0] <= 16'd0;
										end
									end else
										cur_val[0] <= {SAMPLE_ROM_DATA, 8'h00};	// Use first fetch
								end else if (CYCLE_COUNT == 6'd6) begin
									if (REFETCH)
										cur_val[0] <= {SAMPLE_ROM_DATA, 8'h00};	// Use second fetch
								end
							end
							
							2'b01: begin	// 16bit PCM little endian
								if (CYCLE_COUNT == 6'd4) begin
									cur_pfrac[0] <= cur_pfrac[0] + (CH_TYPE[0][5] ? -CH_PITCH[0] : CH_PITCH[0]);	// cur_pfrac += delta;
									// TODO: while(cur_pfrac & FFFF0000) {	// Wtf ?
									if (CH_TYPE[0][5]) begin	//	cur_pos += (pdelta<<1), cur_pfrac += fdelta
										cur_pfrac[0] <= cur_pfrac[0] + 32'h10000;
										cur_pos[0] <= cur_pos[0] - 2'd2;
									end else begin
										cur_pfrac[0] <= cur_pfrac[0] - 32'h10000;
										cur_pos[0] <= cur_pos[0] + 2'd2;
									end
									cur_pval[0] <= cur_val[0];	//	cur_pval = cur_val;
									SAMPLE_ROM_ADDR <= cur_pos[0];
									REFETCH <= 1'b0;
								end else if (CYCLE_COUNT == 6'd5) begin
									cur_val[0][7:0] <= SAMPLE_ROM_DATA;	// LSB
									SAMPLE_ROM_ADDR <= cur_pos[0] + 1'b1;
								end else if (CYCLE_COUNT == 6'd6) begin
									if ({SAMPLE_ROM_DATA, cur_val[0][7:0]} == 16'h8000) begin
										if (CH_LOOP[0]) begin
											cur_pos[0] <= CH_LOOP_POS[0];
											SAMPLE_ROM_ADDR <= CH_LOOP_POS[0];
											REFETCH <= 1'b1;
										end else begin
											// keyoff(0):
											if (!REG_CTRL[7])
												REG_CH_ACTIVE[0] <= 1'b0;
											cur_val[0] <= 16'd0;
										end
									end else
										cur_val[0][15:8] <= SAMPLE_ROM_DATA;	// Use first fetch
								end else if (CYCLE_COUNT == 6'd7) begin
									if (REFETCH) begin
										cur_val[0][7:0] <= SAMPLE_ROM_DATA;		// Use second fetch - LSB
										SAMPLE_ROM_ADDR <= cur_pos[0] + 1'b1;
									end
								end else if (CYCLE_COUNT == 6'd8) begin
									if (REFETCH)
										cur_val[0][15:8] <= SAMPLE_ROM_DATA;	// Use second fetch - MSB
								end
							end
							
							2'b10: begin	// 4bit DPCM
								if (CYCLE_COUNT == 6'd4) begin
									// TODO: Don't do the following =<<'s and ->>'s ! Instead, do it properly:
									// TODO: cur_pfrac needs an additionnal bit for nibble precision, shift it << 1 for all other formats
									// TODO: cur_pos needs an additionnal bit for nibble precision, shift it << 1 for all other formats
									// if cur_pfrac[16]: cur_pfrac &= 0FFFF, cur_pos |= 1
									if (cur_pfrac[0][15])
										temp_cur_pos <= {cur_pos[0], 1'b1};
									else
										temp_cur_pos <= {cur_pos[0], 1'b0};
									temp_cur_pfrac <= {1'b0, cur_pfrac[0][14:0], 1'b0};
								end else if (CYCLE_COUNT == 6'd5) begin
									cur_pfrac[0] <= cur_pfrac[0] + (CH_TYPE[0][5] ? -CH_PITCH[0] : CH_PITCH[0]);	// cur_pfrac += delta;
									// TODO: while(cur_pfrac & FFFF0000) {	// Wtf ?
									if (CH_TYPE[0][5]) begin	//	cur_pos += (pdelta<<1), cur_pfrac += fdelta
										temp_cur_pfrac <= temp_cur_pfrac + 32'h10000;
										temp_cur_pos <= temp_cur_pos - 2'd2;
									end else begin
										temp_cur_pfrac <= temp_cur_pfrac - 32'h10000;
										temp_cur_pos <= temp_cur_pos + 2'd2;
									end
									cur_pval[0] <= cur_val[0];	//	cur_pval = cur_val;
									SAMPLE_ROM_ADDR <= {1'b0, temp_cur_pos[23:1]};	// cur_val = SAMPLE_ROM[cur_pos >> 1]
									REFETCH <= 1'b0;
								end else if (CYCLE_COUNT == 6'd6) begin
									if (SAMPLE_ROM_DATA == 8'h88) begin
										if (CH_LOOP[0]) begin
											temp_cur_pos <= {CH_LOOP_POS[0], 1'b0};
											SAMPLE_ROM_ADDR <= CH_LOOP_POS[0];	// CH_LOOP_POS[0] <<1 then >>1
											REFETCH <= 1'b1;
										end else begin
											// keyoff(0):
											if (!REG_CTRL[7])
												REG_CH_ACTIVE[0] <= 1'b0;
											cur_val[0] <= 16'd0;
										end
									end else
										cur_val[0] <= {8'h00, SAMPLE_ROM_DATA};	// Use first fetch
								end else if (CYCLE_COUNT == 6'd7) begin
									if (REFETCH)
										cur_val[0] <= {8'h00, SAMPLE_ROM_DATA};	// Use second fetch
								end else if (CYCLE_COUNT == 6'd8) begin
									DPCM_INDEX <= temp_cur_pos[0] ? cur_val[0][7:4] : cur_val[0][3:0];
								end else if (CYCLE_COUNT == 6'd9) begin
									cur_val[0] <= cur_pval[0] + DPCM_DATA;
								end else if (CYCLE_COUNT == 6'd10) begin
									// Cap to -32768/+32767
									if (DPCM_DATA[7] & (cur_val[0] < -16'd32768))
										cur_val[0] <= -16'd32768;
									else if (!DPCM_DATA[7] & (cur_val[0] > 16'd32767))
										cur_val[0] <= 16'd32767;
								end else if (CYCLE_COUNT == 6'd11) begin
									// cur_pfrac >>= 1
									// if cur_pos[0]: cur_pfrac |= 0x8000
									cur_pfrac[0] <= {temp_cur_pos[0], temp_cur_pfrac[14:0]};
									// cur_pos >>= 1
									cur_pos[0] <= {1'b0, temp_cur_pos[23:1]};
								end
							end
							
							2'b11: begin
								// If data type == 3: Unknown format, shouldn't happen ?
							end
						endcase

						// Mix channel in
						//lval <= lval + (cur_val * lvol);
						//rval <= rval + (cur_val * rvol);
						lval <= lval + (cur_val[0] * CH_MAIN_VOL[0]);	// TODO: Compute lvol and rvol from CH_PAN and CH_MAIN_VOL
						rval <= rval + (cur_val[0] * CH_MAIN_VOL[0]);
						
						// Update REVERB_RAM
						// REVERB_RAM[rdelta + reverb_pos] += cur_val * rbvol;
						if (CYCLE_COUNT == 6'd20) begin
							// Ask for MSB
							REVERB_RAM_ADDR <= {rdelta + reverb_pos, 1'b0};
							REVERB_RAM_RD <= 1'b1;
						end else if (CYCLE_COUNT == 6'd21) begin
							// Get MSB, ask for LSB
							REVERB_RAM_ADDR <= REVERB_RAM_ADDR + 1'b1;
							REVERB_DATA_TEMP[7:0] <= REVERB_RAM_DATA_OUT;
						end else if (CYCLE_COUNT == 6'd22) begin
							// Get LSB, compute new value
							REVERB_DATA_TEMP <= {REVERB_DATA_TEMP[7:0], REVERB_RAM_DATA_OUT} + (cur_val[0] * 8'd127);	// TODO: Use rbvol
						end else if (CYCLE_COUNT == 6'd23) begin
							// Ask to store MSB
							REVERB_RAM_ADDR <= {rdelta + reverb_pos, 1'b0};
							REVERB_RAM_DATA_IN <= REVERB_DATA_TEMP[15:8];
							REVERB_RAM_RD <= 1'b0;
							REVERB_RAM_WR <= 1'b1;
						end else if (CYCLE_COUNT == 6'd24) begin
							// Stored MSB, ask to store LSB
							REVERB_RAM_ADDR <= REVERB_RAM_ADDR + 1'b1;
							REVERB_RAM_DATA_IN <= REVERB_DATA_TEMP[7:0];
						end else if (CYCLE_COUNT == 6'd25) begin
							// Stored LSB
							REVERB_RAM_WR <= 1'b0;
						end
						
						// Update CH_START
						if (CYCLE_COUNT == 6'd46) begin
							chan_pos[0] <= cur_pos[0];
							if (!REG_CTRL[7])
								CH_START_POS[0] <= cur_pos[0];
						end
					end
				
					AUDIO_OUT_L <= lval;
					AUDIO_OUT_R <= rval;
					reverb_pos <= reverb_pos + 1'b1;
				end
			end
		end
	end
end

endmodule
