// Z80 CPU plug into TV80 core

module cpu_z80(
	input CLK,
	input nRESET,
	input [7:0] SDD_IN,
	output [7:0] SDD_OUT,
	output [15:0] SDA,
	output reg nIORQ,
	output nMREQ,
	output reg nRD, nWR,
	input nINT, nNMI, nWAIT
);

	wire RFSH_n, MREQ_n;
	assign nMREQ = MREQ_n | ~RFSH_n;

	T80s cpu(
		.RESET_n(nRESET),
		.CLK(CLK),
		.CEN(1),
		.WAIT_n(nWAIT),
		.INT_n(nINT),
		.NMI_n(nNMI),
		.MREQ_n(MREQ_n),
		.IORQ_n(nIORQ),
		.RD_n(nRD),
		.WR_n(nWR),
		.RFSH_n(RFSH_n),
		.A(SDA),
		.DI(SDD_IN),
		.DO(SDD_OUT)
	);

endmodule
