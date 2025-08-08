//-----------------------------------------------------------------------------
// File:    eth_router_3_port.sv
//
// Author:  Ian Buckley, Ion Concepts LLC.
//
// Description:
// 3 port router that can switch based on deep packet inspection upto L4.
// 2 ports are always Ethernet protocol, but the third port is configurable
// as either DRaT (With L1-L4 stripped) or IPv4 (WIth L1 stripped).
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-----------------------------------------------------------------------------
`default_nettype none
`include "global_defs.svh"
`include "ethernet.sv"


module eth_router_3_port
  (
   input wire        clk,
   input wire        rst,
   //-------------------------------------------------------------------------------
   // CSR regs Classifer0
   //-------------------------------------------------------------------------------
   input wire [47:0] csr_classifier0_mac,
   input wire [31:0] csr_classifier0_ip,
   input wire [15:0] csr_classifier0_udp0,
   input wire [15:0] csr_classifier0_udp1,
   input wire        csr_classifier0_udp0_enable,
   input wire        csr_classifier0_udp1_enable,
   input wire        csr_classifier0_l3_route_enable,
   input wire        csr_classifier0_expose_drat,
   input wire        csr_classifier0_enable,
   //-------------------------------------------------------------------------------
   // CSR regs Classifer1
   //-------------------------------------------------------------------------------
   input wire [47:0] csr_classifier1_mac,
   input wire [31:0] csr_classifier1_ip,
   input wire [15:0] csr_classifier1_udp0,
   input wire [15:0] csr_classifier1_udp1,
   input wire        csr_classifier1_udp0_enable,
   input wire        csr_classifier1_udp1_enable,
   input wire        csr_classifier1_l3_route_enable,
   input wire        csr_classifier1_expose_drat,
   input wire        csr_classifier1_enable,
   //-------------------------------------------------------------------------------
   // CSR regs Framer0
   //-------------------------------------------------------------------------------
   input wire [47:0] csr_framer0_mac_dst,
   input wire [47:0] csr_framer0_mac_src,
   input wire [31:0] csr_framer0_ipv4_dst,
   input wire [31:0] csr_framer0_ipv4_src,
   input wire [15:0] csr_framer0_udp_src,
   input wire [15:0] csr_framer0_udp_dst0,
   input wire [15:0] csr_framer0_udp_dst1,
   input wire [15:0] csr_framer0_udp_dst2,
   input wire [15:0] csr_framer0_udp_dst3,
   input wire [15:0] csr_framer0_udp_dst4,
   input wire [15:0] csr_framer0_udp_dst5,
   input wire [15:0] csr_framer0_udp_dst6,
   input wire [15:0] csr_framer0_udp_dst7,
   input wire [9:0]  csr_framer0_udp_dst8,

   input wire        csr_framer0_enable,
   output logic      csr_framer0_idle,
   //-------------------------------------------------------------------------------
   // CSR regs Framer0
   //-------------------------------------------------------------------------------
   input wire [47:0] csr_framer1_mac_dst,
   input wire [47:0] csr_framer1_mac_src,
   input wire [31:0] csr_framer1_ipv4_dst,
   input wire [31:0] csr_framer1_ipv4_src,
   input wire [15:0] csr_framer1_udp_src,
   input wire [15:0] csr_framer1_udp_dst0,
   input wire [15:0] csr_framer1_udp_dst1,
   input wire [15:0] csr_framer1_udp_dst2,
   input wire [15:0] csr_framer1_udp_dst3,
   input wire [15:0] csr_framer1_udp_dst4,
   input wire [15:0] csr_framer1_udp_dst5,
   input wire [15:0] csr_framer1_udp_dst6,
   input wire [15:0] csr_framer1_udp_dst7,
   input wire [9:0] csr_framer1_udp_dst8,

   input wire        csr_framer1_enable,
   output logic      csr_framer1_idle,
   //-------------------------------------------------------------------------------
   // External Eth Port0
   //-------------------------------------------------------------------------------
   axis_t.slave in0_axis,
   axis_t.master out0_axis,
   //-------------------------------------------------------------------------------
   // External Eth Port1
   //-------------------------------------------------------------------------------
   axis_t.slave in1_axis,
   axis_t.master out1_axis,
   //-------------------------------------------------------------------------------
   // Internal Eth or DRaT Port 2
   //-------------------------------------------------------------------------------
   axis_t.slave in2out0_axis,
   axis_t.master out2in0_axis,
   axis_t.slave in2out1_axis,
   axis_t.master out2in1_axis
   );

   // Can fit one jumbo (8000) packet in FIFO.
   localparam         CROSSOVER_FIFO_SIZE = 10;
   localparam         EGRESS_FIFO_SIZE = 10;

   // Buses from outputs of packet gates
   axis_t #(.WIDTH(68)) in0_gated_axis(.clk(clk));
   axis_t #(.WIDTH(68)) in1_gated_axis(.clk(clk));
   // Port0 classifier outputs
   axis_t #(.WIDTH(68)) out1in0_axis(.clk(clk));
   //axis_t #(.WIDTH(68)) out2in0_axis(.clk(clk)); // Might need a FIFO
   // Port1 classifier outputs
   axis_t #(.WIDTH(68)) out0in1_axis(.clk(clk));
   //axis_t #(.WIDTH(68)) out2in1_axis(.clk(clk)); // Might need a FIFO
   // Port 0/1 Crossover FIFO outputs
   axis_t #(.WIDTH(68)) out0in1_fifo_axis(.clk(clk));
   axis_t #(.WIDTH(68)) out1in0_fifo_axis(.clk(clk));
   // Port 0 Egress paths
   axis_t #(.WIDTH(68)) null0_axis(.clk(clk));
   axis_t #(.WIDTH(68)) null1_axis(.clk(clk));
   axis_t #(.WIDTH(68)) out0_fifo_axis(.clk(clk));
   // Port 0 Egress paths
   axis_t #(.WIDTH(68)) null2_axis(.clk(clk));
   axis_t #(.WIDTH(68)) null3_axis(.clk(clk));
   axis_t #(.WIDTH(68)) out1_fifo_axis(.clk(clk));
   // Port2 Framer outputs
   axis_t #(.WIDTH(68)) out0in2_framer_axis(.clk(clk));
   axis_t #(.WIDTH(68)) out0in2_fifo_axis(.clk(clk));
   axis_t #(.WIDTH(68)) out1in2_framer_axis(.clk(clk));
   axis_t #(.WIDTH(68)) out1in2_fifo_axis(.clk(clk));

   // TODO: Switch this with DRaT equivalent (axis_packet_fifo with error signal)
   //
   // Packet gate ensures on entire ingressing packet is buffered before feeding it downstream so that it bursts
   // efficiently internally without holding resources allocted for longer than optimal. This also means that an upstream
   // error signalled by the MAC can allow the packet to be destroyed here, before it gets deeper into the system.
   //
   // This gate must be able to hold at least 9900 bytes to suport jumbo packets.
   // With SIZE=11, this gate will hold 2 8k packets.

   axi_packet_gate_wrapper #( .SIZE(11), .USE_AS_BUFF(1)) packet_gate_wrapper_i0
     (
      .clk(clk),
      .reset(rst),
      .error(in0_axis.tdata[in0_axis.WIDTH-1]),
      .in_axis(in0_axis),
      .out_axis(in0_gated_axis)
      );

    axi_packet_gate_wrapper #( .SIZE(11), .USE_AS_BUFF(1)) packet_gate_wrapper_i1
     (
      .clk(clk),
      .reset(rst),
      .error(in1_axis.tdata[in1_axis.WIDTH-1]),
      .in_axis(in1_axis),
      .out_axis(in1_gated_axis)
      );


   //---------------------------------------------------------
   // Deep pcket inspection L1 through L4 to classify ingress.
   // Switch between egress to core or cross over ethrenet
   //---------------------------------------------------------
   wire [25:0] 	      classifier_dbg;

   eth_classifier_2_egress eth_classifier_2_egress_i0
     (
      .clk(clk),
      .rst(rst),
      //
      // Ingress ethernet bus to classify
      //
      .in_axis(in0_gated_axis),
      //
      // Two possible egress busses.
      //
      .out0_axis(out1in0_axis),      // Assumed to be default, with full TCP/IP stack downstream, 4 tuser bits included
      .out1_axis(out2in0_axis),      // Assumed to be DRaT protocol datapath, no tuser bits included.
      //
      // CSR
      //
      .csr_mac(csr_classifier0_mac),
      .csr_ip(csr_classifier0_ip),
      .csr_udp0(csr_classifier0_udp0),
      .csr_udp1(csr_classifier0_udp1),
      .csr_udp0_enable(csr_classifier0_udp0_enable),
      .csr_udp1_enable(csr_classifier0_udp1_enable),
      .csr_l3_route_enable(csr_classifier0_l3_route_enable),
      .csr_expose_drat(csr_classifier0_expose_drat),
      .csr_enable(csr_classifier0_enable)
   );

   eth_classifier_2_egress eth_classifier_2_egress_i1
     (
      .clk(clk),
      .rst(rst),
      //
      // Ingress ethernet bus to classify
      //
      .in_axis(in1_gated_axis),
      //
      // Two possible egress busses.
      //
      .out0_axis(out0in1_axis),      // Assumed to be default, with full TCP/IP stack downstream, 4 tuser bits included
      .out1_axis(out2in1_axis),      // Assumed to be DRaT protocol datapath, no tuser bits included.
      //
      // CSR
      //
      .csr_mac(csr_classifier1_mac),
      .csr_ip(csr_classifier1_ip),
      .csr_udp0(csr_classifier1_udp0),
      .csr_udp1(csr_classifier1_udp1),
      .csr_udp0_enable(csr_classifier1_udp0_enable),
      .csr_udp1_enable(csr_classifier1_udp1_enable),
      .csr_l3_route_enable(csr_classifier1_l3_route_enable),
      .csr_expose_drat(csr_classifier1_expose_drat),
      .csr_enable(csr_classifier1_enable)
      );

   //---------------------------------------------------------
   // Buffer crossover paths in both directions to reduce
   // arbitration stalls and backproessure.
   //---------------------------------------------------------
   axis_fifo_wrapper
     #(
       .SIZE(CROSSOVER_FIFO_SIZE)
       )
   axis_fifo_crossover_i0
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out0in1_axis),
      .out_axis(out0in1_fifo_axis),
      .space(),
      .occupied()
      );

   axis_fifo_wrapper
     #(
       .SIZE(CROSSOVER_FIFO_SIZE)
       )
   axis_fifo_crossover_i1
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out1in0_axis),
      .out_axis(out1in0_fifo_axis),
      .space(),
      .occupied()
      );

   //---------------------------------------------------------
   // Mux each crossover path with packets egressing the core
   // (Round Robin arbitration for fair sharing)
   //---------------------------------------------------------
   // Port0
   axis_mux4_wrapper
     #(
       .BUFFER(0),
       .PRIORITY(0))
   egress_mux_i0
     (
      .clk(clk),
      .rst(rst),
      .in0_axis(out0in1_fifo_axis),
      .in1_axis(out0in2_fifo_axis),
      .in2_axis(null0_axis),
      .in3_axis(null1_axis),
      .out_axis(out0_fifo_axis)
   );

   axis_null_src axis_null_src_i0
     (
      .out_axis(null0_axis)
      );

   axis_null_src axis_null_src_i1
     (
      .out_axis(null1_axis)
      );

   // Port1
   axis_mux4_wrapper
     #(
       .BUFFER(0),
       .PRIORITY(0))
   egress_mux_i1
     (
      .clk(clk),
      .rst(rst),
      .in0_axis(out1in0_fifo_axis),
      .in1_axis(out1in2_fifo_axis),
      .in2_axis(null2_axis),
      .in3_axis(null3_axis),
      .out_axis(out1_fifo_axis)
   );

   axis_null_src axis_null_src_i2
     (
      .out_axis(null2_axis)
      );

   axis_null_src axis_null_src_i3
     (
      .out_axis(null3_axis)
      );

   //---------------------------------------------------------
   // Egress FIFOs towards external Ethernet stop back pressure
   // from slow ethernet ports propogating upstream.
   //---------------------------------------------------------
   axis_fifo_wrapper
     #(
       .SIZE(EGRESS_FIFO_SIZE)
       )
   axis_fifo_egress_i0
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out0_fifo_axis),
      .out_axis(out0_axis),
      .space(),
      .occupied()
      );

   axis_fifo_wrapper
     #(
       .SIZE(EGRESS_FIFO_SIZE)
       )
   axis_fifo_egress_i1
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out1_fifo_axis),
      .out_axis(out1_axis),
      .space(),
      .occupied()
      );

   //---------------------------------------------------------
   // Framer
   //
   //---------------------------------------------------------
   drat2eth_framer framer_i0
     (
      .clk(clk),
      .rst(rst),
      // CSR interface
      .csr_mac_dst(csr_framer0_mac_dst),
      .csr_mac_src(csr_framer0_mac_src),
      .csr_ipv4_dst(csr_framer0_ipv4_dst),
      .csr_ipv4_src(csr_framer0_ipv4_src),
      .csr_udp_src(csr_framer0_udp_src),
      .csr_udp_dst0(csr_framer0_udp_dst0),
      .csr_udp_dst1(csr_framer0_udp_dst1),
      .csr_udp_dst2(csr_framer0_udp_dst2),
      .csr_udp_dst3(csr_framer0_udp_dst3),
      .csr_udp_dst4(csr_framer0_udp_dst4),
      .csr_udp_dst5(csr_framer0_udp_dst5),
      .csr_udp_dst6(csr_framer0_udp_dst6),
      .csr_udp_dst7(csr_framer0_udp_dst7),
      .csr_udp_dst8(csr_framer0_udp_dst8),

      .csr_enable(csr_framer0_enable),
      .csr_idle(csr_framer0_idle),

      // DRaT protocol input bus (64b TDATA)
      .in_axis(in2out0_axis),
      // Ethernet/IPv4/UDP encapsulated output bus (68b TDATA)
      .out_axis(out0in2_framer_axis)
      );

   axis_minimal_fifo_wrapper framer_fifo_i0
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out0in2_framer_axis),
      .out_axis(out0in2_fifo_axis),
      .space_out(),
      .occupied_out()
      );

   drat2eth_framer framer_i1
     (
      .clk(clk),
      .rst(rst),
      // CSR interface
      .csr_mac_dst(csr_framer1_mac_dst),
      .csr_mac_src(csr_framer1_mac_src),
      .csr_ipv4_dst(csr_framer1_ipv4_dst),
      .csr_ipv4_src(csr_framer1_ipv4_src),
      .csr_udp_src(csr_framer1_udp_src),
      .csr_udp_dst0(csr_framer1_udp_dst0),
      .csr_udp_dst1(csr_framer1_udp_dst1),
      .csr_udp_dst2(csr_framer1_udp_dst2),
      .csr_udp_dst3(csr_framer1_udp_dst3),
      .csr_udp_dst4(csr_framer1_udp_dst4),
      .csr_udp_dst5(csr_framer1_udp_dst5),
      .csr_udp_dst6(csr_framer1_udp_dst6),
      .csr_udp_dst7(csr_framer1_udp_dst7),
      .csr_udp_dst8(csr_framer1_udp_dst8),

      .csr_enable(csr_framer1_enable),
      .csr_idle(csr_framer1_idle),

      // DRaT protocol input bus (64b TDATA)
      .in_axis(in2out1_axis),
      // Ethernet/IPv4/UDP encapsulated output bus (68b TDATA)
      .out_axis(out1in2_framer_axis)
      );

   axis_minimal_fifo_wrapper framer_fifo_i1
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out1in2_framer_axis),
      .out_axis(out1in2_fifo_axis),
      .space_out(),
      .occupied_out()
      );


   //-------------------------------------------------------------------------------
   // Debug Only below
   //-------------------------------------------------------------------------------
/* -----\/----- EXCLUDED -----\/-----
   wire [63:0] probe ; // Debug
   //assign probe = 64'h0;

  // assign probe[7:0] = axil_csr.ar_addr[7:0];
  // assign probe[8] = axil_csr.ar_ready;
  // assign probe[9] = axil_csr.ar_valid;
  // assign probe[10] = axil_csr.r_ready;
 //  assign probe[11] = axil_csr.r_valid;
  // assign probe[12] = axil_csr.r_resp;
 //  assign probe[31:13] = 0;
   assign probe[7:0] = in0_axis.tdata[63:56];

   assign probe[8] = in0_axis.tready;    // SPI Master In
   assign probe[9] = in0_axis.tvalid;    // SPI Master Out
   assign probe[10] = in0_axis.tlast; // SPI CLK
   assign probe[11] = in0_gated_axis.tready;    // SPI Master In
   assign probe[12] = in0_gated_axis.tvalid;    // SPI Master Out
   assign probe[13] = in0_gated_axis.tlast; // SPI CLK

   assign probe[23:16] = in0_gated_axis.tdata[63:56];

   assign probe[49:24] = classifier_dbg[25:0];

   assign probe[50] = out1in0_axis.tready;
   assign probe[51] = out1in0_axis.tvalid;
   assign probe[52] = out1in0_axis.tlast;

   assign probe[53] = out2in0_axis.tready;
   assign probe[54] = out2in0_axis.tvalid;
   assign probe[55] = out2in0_axis.tlast;

   assign probe[56] = out1in0_fifo_axis.tready;
   assign probe[57] = out1in0_fifo_axis.tvalid;
   assign probe[58] = out1in0_fifo_axis.tlast;

   assign probe[59] = out1_fifo_axis.tready;
   assign probe[60] = out1_fifo_axis.tvalid;
   assign probe[61] = out1_fifo_axis.tlast;

   assign probe[63:62] =0;

   ila_64 ila_64_i0 (
	.clk(clk), // input wire clk

	.probe0(probe[0]), // input wire [0:0]  probe0
	.probe1(probe[1]), // input wire [0:0]  probe1
	.probe2(probe[2]), // input wire [0:0]  probe2
	.probe3(probe[3]), // input wire [0:0]  probe3
	.probe4(probe[4]), // input wire [0:0]  probe4
	.probe5(probe[5]), // input wire [0:0]  probe5
	.probe6(probe[6]), // input wire [0:0]  probe6
	.probe7(probe[7]), // input wire [0:0]  probe7
	.probe8(probe[8]), // input wire [0:0]  probe8
	.probe9(probe[9]), // input wire [0:0]  probe9
	.probe10(probe[10]), // input wire [0:0]  probe10
	.probe11(probe[11]), // input wire [0:0]  probe11
	.probe12(probe[12]), // input wire [0:0]  probe12
	.probe13(probe[13]), // input wire [0:0]  probe13
	.probe14(probe[14]), // input wire [0:0]  probe14
	.probe15(probe[15]), // input wire [0:0]  probe15
	.probe16(probe[16]), // input wire [0:0]  probe16
	.probe17(probe[17]), // input wire [0:0]  probe17
	.probe18(probe[18]), // input wire [0:0]  probe18
	.probe19(probe[19]), // input wire [0:0]  probe19
	.probe20(probe[20]), // input wire [0:0]  probe20
	.probe21(probe[21]), // input wire [0:0]  probe21
	.probe22(probe[22]), // input wire [0:0]  probe22
	.probe23(probe[23]), // input wire [0:0]  probe23
	.probe24(probe[24]), // input wire [0:0]  probe24
	.probe25(probe[25]), // input wire [0:0]  probe25
	.probe26(probe[26]), // input wire [0:0]  probe26
	.probe27(probe[27]), // input wire [0:0]  probe27
	.probe28(probe[28]), // input wire [0:0]  probe28
	.probe29(probe[29]), // input wire [0:0]  probe29
	.probe30(probe[30]), // input wire [0:0]  probe30
	.probe31(probe[31]), // input wire [0:0]  probe31
	.probe32(probe[32]), // input wire [0:0]  probe32
	.probe33(probe[33]), // input wire [0:0]  probe33
	.probe34(probe[34]), // input wire [0:0]  probe34
	.probe35(probe[35]), // input wire [0:0]  probe35
	.probe36(probe[36]), // input wire [0:0]  probe36
	.probe37(probe[37]), // input wire [0:0]  probe37
	.probe38(probe[38]), // input wire [0:0]  probe38
	.probe39(probe[39]), // input wire [0:0]  probe39
	.probe40(probe[40]), // input wire [0:0]  probe40
	.probe41(probe[41]), // input wire [0:0]  probe41
	.probe42(probe[42]), // input wire [0:0]  probe42
	.probe43(probe[43]), // input wire [0:0]  probe43
	.probe44(probe[44]), // input wire [0:0]  probe44
	.probe45(probe[45]), // input wire [0:0]  probe45
	.probe46(probe[46]), // input wire [0:0]  probe46
	.probe47(probe[47]), // input wire [0:0]  probe47
	.probe48(probe[48]), // input wire [0:0]  probe48
	.probe49(probe[49]), // input wire [0:0]  probe49
	.probe50(probe[50]), // input wire [0:0]  probe50
	.probe51(probe[51]), // input wire [0:0]  probe51
	.probe52(probe[52]), // input wire [0:0]  probe52
	.probe53(probe[53]), // input wire [0:0]  probe53
	.probe54(probe[54]), // input wire [0:0]  probe54
        .probe55(probe[55]), // input wire [0:0]  probe55
	.probe56(probe[56]), // input wire [0:0]  probe56
	.probe57(probe[57]), // input wire [0:0]  probe57
	.probe58(probe[58]), // input wire [0:0]  probe58
	.probe59(probe[59]), // input wire [0:0]  probe59
	.probe60(probe[60]), // input wire [0:0]  probe60
	.probe61(probe[61]), // input wire [0:0]  probe61
	.probe62(probe[62]), // input wire [0:0]  probe62
	.probe63(probe[63]) // input wire [0:0]  probe63
);
 -----/\----- EXCLUDED -----/\----- */

endmodule // eth_router_3_port

`default_nettype wire
