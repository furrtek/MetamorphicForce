module tb_z80(
);

reg CLK;
reg nRESET;

wire [7:0] SDD_IN;
wire [7:0] SDD_OUT;
wire [15:0] SDA;
wire nIORQ, nRD, nWR;
reg nMREQ, nINT, nNMI, nWAIT;

cpu_z80 Z80(
	CLK,	// 8MHz
	nRESET,
	SDD_IN, SDD_OUT, SDA,
	nIORQ, nMREQ,
	nRD, nWR,
	nINT, nNMI, nWAIT
);

assign SDD_IN = 8'h00;	// TODO

initial begin
	CLK <= 0;
	nRESET <= 0;
	nRD <= 1;
	nWR <= 1;
	nINT <= 1;
	nNMI <= 1;
	nWAIT <= 1;
	#10
	nRESET <= 1;
	#10
	$finish
end

always
	#1 CLK <= ~CLK;

endmodule
