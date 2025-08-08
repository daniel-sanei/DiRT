//-------------------------------------------------------------------------------
// File:    eth_router_3_port_unit_test.sv
//
// Description:
//
//-------------------------------------------------------------------------------
`include "global_defs.svh"
`include "svunit_defines.svh"
`include "eth_router_3_port.sv"
`include "drat_protocol.sv"

module eth_router_3_port_unit_test;
   timeunit 1ns;
   timeprecision 1ps;
   //import drat_protocol::*;
   import ethernet_protocol::*;
   import drat_protocol::*;
   import svunit_pkg::svunit_testcase;

   string name = "eth_router_3_port_ut";
   svunit_testcase svunit_ut;

   // Enumeration of test values used repeatedly in bench
   localparam TEST_DRAT_SIZE = 'd16;
   localparam TEST_IPV4_DST = {8'd5,8'd6,8'd7,8'd8};
   localparam TEST_IPV4_SRC = {8'd1,8'd2,8'd3,8'd4};
   localparam TEST_MAC_DST = {8'd0,8'd6,8'd7,8'd8,8'd9,8'd10};
   localparam TEST_MAC_SRC = {8'd0,8'd1,8'd2,8'd3,8'd4,8'd5};


   logic clk;
   logic rst;

   //---------------------------------------------------
   //
   // Port 0: PCS/PMA
   //    eth_stream_t ingress
   //    eth_stream_t egress
   //
   // Pre-Buffer Input Bus
   eth_stream_t in0_axis_pre(.clk(clk));
   // Bus between stimulus buffer and valve
   eth_stream_t in0_axis_post(.clk(clk));
   // Bus between valve and UUT
   eth_stream_t in0_axis(.clk(clk));
   // Bus between UUT egress0 and egress valve
   eth_stream_t out0_axis(.clk(clk));
   // Bus between egress0 valve and FIFO
   eth_stream_t out0_axis_pre(.clk(clk));
   // Bus between egress0 FIFO and response test bench
   eth_stream_t out0_axis_post(.clk(clk));
   // Golden response buses for FIFO's
   eth_stream_t out0_axis_in_golden(.clk(clk));
   eth_stream_t out0_axis_out_golden(.clk(clk));
   //
   //---------------------------------------------------
   //
   // Port 1: GEM0
   //    eth_stream_t ingress
   //    eth_stream_t egress
   //
   // Pre-Buffer Input Bus
   eth_stream_t in1_axis_pre(.clk(clk));
   // Bus between stimulus buffer and valve
   eth_stream_t in1_axis_post(.clk(clk));
   // Bus between valve and UUT
   eth_stream_t in1_axis(.clk(clk));
   // Bus between UUT egress1 and egress valve
   eth_stream_t out1_axis(.clk(clk));
   // Bus between egress1 valve and FIFO
   eth_stream_t out1_axis_pre(.clk(clk));
   // Bus between egress1 FIFO and response test bench
   eth_stream_t out1_axis_post(.clk(clk));
   // Golden response buses for FIFO's
   eth_stream_t out1_axis_in_golden(.clk(clk));
   eth_stream_t out1_axis_out_golden(.clk(clk));
   //
   //---------------------------------------------------
   //
   // Port 2: PL
   //    2x eth_stream_t ingress
   //    2x eth_stream_t egress
   //
   // Pre-Buffer Input Bus
   eth_stream_t in2out0_axis_pre(.clk(clk));
   // Bus between stimulus buffer and valve
   eth_stream_t in2out0_axis_post(.clk(clk));
   // Bus between valve and UUT
   eth_stream_t in2out0_axis(.clk(clk));
   // Bus between UUT egress2 and egress valve
   axis_t #(.WIDTH(64)) out2in0_axis(.clk(clk));
   // Bus between egress2 valve and FIFO
   axis_t #(.WIDTH(64)) out2in0_axis_pre(.clk(clk));
   // Bus between egress2 FIFO and response test bench
   axis_t #(.WIDTH(64)) out2in0_axis_post(.clk(clk));
   // Pre-Buffer Input Bus
   eth_stream_t in2out1_axis_pre(.clk(clk));
   // Bus between stimulus buffer and valve
   eth_stream_t in2out1_axis_post(.clk(clk));
   // Bus between valve and UUT
   eth_stream_t in2out1_axis(.clk(clk));
   // Bus between UUT egress2 and egress valve
   axis_t #(.WIDTH(64)) out2in1_axis(.clk(clk));
   // Bus between egress2 valve and FIFO
   axis_t #(.WIDTH(64)) out2in1_axis_pre(.clk(clk));
   // Bus between egress2 FIFO and response test bench
   axis_t #(.WIDTH(64)) out2in1_axis_post(.clk(clk));
   // Golden response buses for FIFO's
   axis_t #(.WIDTH(64)) out2in0_axis_in_golden(.clk(clk));
   axis_t #(.WIDTH(64)) out2in1_axis_in_golden(.clk(clk));
   axis_t #(.WIDTH(64)) out2in0_axis_out_golden(.clk(clk));
   axis_t #(.WIDTH(64)) out2in1_axis_out_golden(.clk(clk));
   //
   //---------------------------------------------------
   //
   // CSR interface
   //
   logic [47:0] csr_classifier0_mac;
   logic [31:0] csr_classifier0_ip;
   logic [15:0] csr_classifier0_udp0;
   logic [15:0] csr_classifier0_udp1;
   logic        csr_classifier0_expose_drat;
   logic        csr_classifier0_enable;
   logic        csr_classifier0_udp0_enable;
   logic        csr_classifier0_udp1_enable;


   logic [47:0] csr_classifier1_mac;
   logic [31:0] csr_classifier1_ip;
   logic [15:0] csr_classifier1_udp0;
   logic [15:0] csr_classifier1_udp1;
   logic        csr_classifier1_expose_drat;
   logic        csr_classifier1_enable;
   logic        csr_classifier1_udp0_enable;
   logic        csr_classifier1_udp1_enable;


   logic [47:0] csr_framer0_mac_dst;
   logic [47:0] csr_framer0_mac_src;
   logic [31:0] csr_framer0_ipv4_dst;
   logic [31:0] csr_framer0_ipv4_src;

   logic [15:0] csr_framer0_udp_src;
   logic [15:0] csr_framer0_udp_dst0;
   logic [15:0] csr_framer0_udp_dst1;
   logic [15:0] csr_framer0_udp_dst2;
   logic [15:0] csr_framer0_udp_dst3;
   logic [15:0] csr_framer0_udp_dst4;
   logic [15:0] csr_framer0_udp_dst5;
   logic [15:0] csr_framer0_udp_dst6;
   logic [15:0] csr_framer0_udp_dst7;

   logic        csr_framer0_enable;
   logic        csr_framer0_idle;

   logic [47:0] csr_framer1_mac_dst;
   logic [47:0] csr_framer1_mac_src;
   logic [31:0] csr_framer1_ipv4_dst;
   logic [31:0] csr_framer1_ipv4_src;

   logic [15:0] csr_framer1_udp_src;
   logic [15:0] csr_framer1_udp_dst0;
   logic [15:0] csr_framer1_udp_dst1;
   logic [15:0] csr_framer1_udp_dst2;
   logic [15:0] csr_framer1_udp_dst3;
   logic [15:0] csr_framer1_udp_dst4;
   logic [15:0] csr_framer1_udp_dst5;
   logic [15:0] csr_framer1_udp_dst6;
   logic [15:0] csr_framer1_udp_dst7;

   logic        csr_framer1_enable;
   logic        csr_framer1_idle;

   // Declarations for Stimulus Thread(s)
   logic        enable_stimulus0;
   logic        enable_stimulus1;
   logic        enable_stimulus2to0;
   logic        enable_stimulus2to1;
   logic        enable_response0;
   logic        enable_response1;
   logic        enable_response2in0;
   logic        enable_response2in1;
   logic        ready_to_test;
   logic [63:0] beat_in;

   // Declarations for Response Thread(s)
   logic [67:0] golden_beat0, response_beat0;
   logic        golden_tlast0, response_tlast0;

   logic [67:0] golden_beat1, response_beat1;
   logic        golden_tlast1, response_tlast1;

   logic [63:0] golden_beat2in0, response_beat2in0;
   logic        golden_tlast2in0, response_tlast2in0;

   logic [63:0] golden_beat2in1, response_beat2in1;
   logic        golden_tlast2in1, response_tlast2in1;

   // Watchdog
   integer      timeout;



   //
   // Generate clk
   //
   initial begin
      clk <= 1'b1;
   end

   always begin
     #5 clk <= ~clk;
   end

   //-------------------------------------------------------------------------------
   // Buffer input stimulus packet stream.
   // Pass first to a FIFO to buffer test stimulus.
   // Then a valve so that the buffer can be loaded, then bursted,
   // at full rate, or be modulated to reduce the rate.
   //-------------------------------------------------------------------------------

   // Port0 Ingress
   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_stimulus_i0
     (
      .clk(clk),
      .rst(rst),
      .in_axis(in0_axis_pre.axis),
      .out_axis(in0_axis_post.axis),
      .space(),
      .occupied()
      );


   axis_valve axis_valve_stimulus_i0
     (
      .clk(clk),
      .rst(rst),
      .in_axis(in0_axis_post.axis),
      .out_axis(in0_axis.axis),
      .enable(enable_stimulus0)
      );

   // Port1 ingress
   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_stimulus_i1
     (
      .clk(clk),
      .rst(rst),
      .in_axis(in1_axis_pre.axis),
      .out_axis(in1_axis_post.axis),
      .space(),
      .occupied()
      );


   axis_valve axis_valve_stimulus_i1
     (
      .clk(clk),
      .rst(rst),
      .in_axis(in1_axis_post.axis),
      .out_axis(in1_axis.axis),
      .enable(enable_stimulus1)
      );

   // Port2->0 Ingress
   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_stimulus_i2
     (
      .clk(clk),
      .rst(rst),
      .in_axis(in2out0_axis_pre.axis),
      .out_axis(in2out0_axis_post.axis),
      .space(),
      .occupied()
      );


   axis_valve axis_valve_stimulus_i2
     (
      .clk(clk),
      .rst(rst),
      .in_axis(in2out0_axis_post.axis),
      .out_axis(in2out0_axis.axis),
      .enable(enable_stimulus1)
      );

   // Port2->1 Ingress
   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_stimulus_i3
     (
      .clk(clk),
      .rst(rst),
      .in_axis(in2out1_axis_pre.axis),
      .out_axis(in2out1_axis_post.axis),
      .space(),
      .occupied()
      );


   axis_valve axis_valve_stimulus_i3
     (
      .clk(clk),
      .rst(rst),
      .in_axis(in2out1_axis_post.axis),
      .out_axis(in2out1_axis.axis),
      .enable(enable_stimulus1)
      );

   //-------------------------------------------------------------------------------
   // Buffer output response packet streams
   //-------------------------------------------------------------------------------

   // Port0 Egress
   axis_valve axis_valve_response_i0
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out0_axis.axis),
      .out_axis(out0_axis_pre.axis),
      .enable(enable_response0)
      );

   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_response_i0
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out0_axis_pre.axis),
      .out_axis(out0_axis_post.axis),
      .space(),
      .occupied()
      );

   // Port1 Egress
   axis_valve axis_valve_response_i1
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out1_axis.axis),
      .out_axis(out1_axis_pre.axis),
      .enable(enable_response1)
      );

   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_response_i1
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out1_axis_pre.axis),
      .out_axis(out1_axis_post.axis),
      .space(),
      .occupied()
      );

   // Port0->2 Egress
   axis_valve axis_valve_response_i2
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out2in0_axis),
      .out_axis(out2in0_axis_pre),
      .enable(enable_response2in0)
      );

   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_response_i2
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out2in0_axis_pre),
      .out_axis(out2in0_axis_post),
      .space(),
      .occupied()
      );

   // Port1->2 Egress
   axis_valve axis_valve_response_i3
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out2in1_axis),
      .out_axis(out2in1_axis_pre),
      .enable(enable_response2in1 )
      );

   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_response_i3
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out2in1_axis_pre),
      .out_axis(out2in1_axis_post),
      .space(),
      .occupied()
      );

   //-------------------------------------------------------------------------------
   // Buffer golden response packet streams.
   // These FIFO's are pre-loaded with expected response by the stimulus side of the test bench.
   // The response side of the test bench drains them whilst comparing the actual response.
   //-------------------------------------------------------------------------------

   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_golden_i0
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out0_axis_in_golden.axis),
      .out_axis(out0_axis_out_golden.axis),
      .space(),
      .occupied()
      );

   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_golden_i1
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out1_axis_in_golden.axis),
      .out_axis(out1_axis_out_golden.axis),
      .space(),
      .occupied()
      );

   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_golden_i2
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out2in0_axis_in_golden),
      .out_axis(out2in0_axis_out_golden),
      .space(),
      .occupied()
      );

   axis_fifo_wrapper
     #(
       .SIZE(16)
       )
   axis_fifo_golden_i3
     (
      .clk(clk),
      .rst(rst),
      .in_axis(out2in1_axis_in_golden),
      .out_axis(out2in1_axis_out_golden),
      .space(),
      .occupied()
      );

   //-------------------------------------------------------------------------------
   // UUT
   //-------------------------------------------------------------------------------
   eth_router_3_port my_eth_router_3_port
     (
      .clk(clk),
      .rst(rst),
      // CSR interface
      // Classifier0
      .csr_classifier0_mac(csr_classifier0_mac),
      .csr_classifier0_ip(csr_classifier0_ip),
      .csr_classifier0_udp0(csr_classifier0_udp0),
      .csr_classifier0_udp1(csr_classifier0_udp1),
      .csr_classifier0_udp0_enable(csr_classifier0_udp0_enable),
      .csr_classifier0_udp1_enable(csr_classifier0_udp1_enable),
      .csr_classifier0_expose_drat(csr_classifier0_expose_drat),
      .csr_classifier0_enable(csr_classifier0_enable),
      // Classifier1
      .csr_classifier1_mac(csr_classifier1_mac),
      .csr_classifier1_ip(csr_classifier1_ip),
      .csr_classifier1_udp0(csr_classifier1_udp0),
      .csr_classifier1_udp1(csr_classifier1_udp1),
      .csr_classifier1_udp0_enable(csr_classifier1_udp0_enable),
      .csr_classifier1_udp1_enable(csr_classifier1_udp1_enable),
      .csr_classifier1_expose_drat(csr_classifier1_expose_drat),
      .csr_classifier1_enable(csr_classifier1_enable),
      //Farmer0
      .csr_framer0_mac_dst(csr_framer0_mac_dst),
      .csr_framer0_mac_src(csr_framer0_mac_src),
      .csr_framer0_ipv4_dst(csr_framer0_ipv4_dst),
      .csr_framer0_ipv4_src(csr_framer0_ipv4_src),
      .csr_framer0_udp_src(csr_framer0_udp_src),
      .csr_framer0_udp_dst0(csr_framer0_udp_dst0),
      .csr_framer0_udp_dst1(csr_framer0_udp_dst1),
      .csr_framer0_udp_dst2(csr_framer0_udp_dst2),
      .csr_framer0_udp_dst3(csr_framer0_udp_dst3),
      .csr_framer0_udp_dst4(csr_framer0_udp_dst4),
      .csr_framer0_udp_dst5(csr_framer0_udp_dst5),
      .csr_framer0_udp_dst6(csr_framer0_udp_dst6),
      .csr_framer0_udp_dst7(csr_framer0_udp_dst7),
      .csr_framer0_enable(csr_framer0_enable),
      .csr_framer0_idle(csr_framer0_idle),
      // Framer1
      .csr_framer1_mac_dst(csr_framer1_mac_dst),
      .csr_framer1_mac_src(csr_framer1_mac_src),
      .csr_framer1_ipv4_dst(csr_framer1_ipv4_dst),
      .csr_framer1_ipv4_src(csr_framer1_ipv4_src),
      .csr_framer1_udp_src(csr_framer1_udp_src),
      .csr_framer1_udp_dst0(csr_framer1_udp_dst0),
      .csr_framer1_udp_dst1(csr_framer1_udp_dst1),
      .csr_framer1_udp_dst2(csr_framer1_udp_dst2),
      .csr_framer1_udp_dst3(csr_framer1_udp_dst3),
      .csr_framer1_udp_dst4(csr_framer1_udp_dst4),
      .csr_framer1_udp_dst5(csr_framer1_udp_dst5),
      .csr_framer1_udp_dst6(csr_framer1_udp_dst6),
      .csr_framer1_udp_dst7(csr_framer1_udp_dst7),
      .csr_framer1_enable(csr_framer1_enable),
      .csr_framer1_idle(csr_framer1_idle),
      // External Eth Port0
      .in0_axis(in0_axis.axis),
      .out0_axis(out0_axis.axis),
      // External Eth Port1
      .in1_axis(in1_axis.axis),
      .out1_axis(out1_axis.axis),
      // Internal Eth or DRaT Port 2
      .in2out0_axis(in2out0_axis.axis),
      .out2in0_axis(out2in0_axis),
      .in2out1_axis(in2out1_axis.axis),
      .out2in1_axis(out2in1_axis)
      );


   //===================================
   // Build
   //===================================
   function void build();
      svunit_ut = new(name);
   endfunction

   //===================================
   // Setup for running the Unit Tests
   //===================================
   task setup();
      svunit_ut.setup();
      /* Place Setup Code Here */
      // Reset UUT
      @(posedge clk);
      rst <= 1'b1;
      ready_to_test <= 0;
      // Bring CSR"s to reset like values.
      csr_classifier0_mac <= 0;
      csr_classifier0_ip <= 0;
      csr_classifier0_udp0 <= 0;
      csr_classifier0_udp1 <= 0;
      csr_classifier0_udp0_enable <= 0;
      csr_classifier0_udp1_enable <= 0;
      csr_classifier0_expose_drat <= 1'b0;
      csr_classifier0_enable <= 1'b0;

      csr_classifier1_mac <= 0;
      csr_classifier1_ip <= 0;
      csr_classifier1_udp0 <= 0;
      csr_classifier1_udp1 <= 0;
      csr_classifier1_udp0_enable <= 0;
      csr_classifier1_udp1_enable <= 0;
      csr_classifier1_expose_drat <= 1'b0;
      csr_classifier1_enable <= 1'b0;

      csr_framer0_mac_dst <= 0;
      csr_framer0_mac_src <= 0;
      csr_framer0_ipv4_dst <= 0;
      csr_framer0_ipv4_src <= 0;
      csr_framer0_udp_src <= 0;
      csr_framer0_udp_dst0 <= 0;
      csr_framer0_udp_dst1 <= 0;
      csr_framer0_udp_dst2 <= 0;
      csr_framer0_udp_dst3 <= 0;
      csr_framer0_udp_dst4 <= 0;
      csr_framer0_udp_dst5 <= 0;
      csr_framer0_udp_dst6 <= 0;
      csr_framer0_udp_dst7 <= 0;
      csr_framer0_enable <= 0;

      csr_framer1_mac_dst <= 0;
      csr_framer1_mac_src <= 0;
      csr_framer1_ipv4_dst <= 0;
      csr_framer1_ipv4_src <= 0;
      csr_framer1_udp_src <= 0;
      csr_framer1_udp_dst0 <= 0;
      csr_framer1_udp_dst1 <= 0;
      csr_framer1_udp_dst2 <= 0;
      csr_framer1_udp_dst3 <= 0;
      csr_framer1_udp_dst4 <= 0;
      csr_framer1_udp_dst5 <= 0;
      csr_framer1_udp_dst6 <= 0;
      csr_framer1_udp_dst7 <= 0;
      csr_framer1_enable <= 0;

      // Open all valves by default
      enable_stimulus0 <= 1'b1;
      enable_stimulus1 <= 1'b1;
      enable_stimulus2to0 <= 1'b1;
      enable_stimulus2to1 <= 1'b1;

      enable_response0 <= 1'b1;
      enable_response1 <= 1'b1;
      enable_response2in0 <= 1'b1;
      enable_response2in1 <= 1'b1;
      // Take all bench AXIS buses to a quiescent state
      idle_all();
      // De-assert reset after 10 clock cycles.
      repeat(10) @(posedge clk);
      rst <= 1'b0;

   endtask


  //===================================
  // Here we deconstruct anything we
  // need after running the Unit Tests
  //===================================
  task teardown();
    svunit_ut.teardown();
    /* Place Teardown Code Here */
  endtask

  //===================================
  // All tests are defined between the
  // SVUNIT_TESTS_BEGIN/END macros
  //
  // Each individual test must be
  // defined between `SVTEST(_NAME_)
  // `SVTEST_END
  //
  // i.e.
  //   `SVTEST(mytest)
  //     <test code>
  //   `SVTEST_END
  //===================================
  `SVUNIT_TESTS_BEGIN

   //-------------------------------------------------------------------------------
   //
   //
   //-------------------------------------------------------------------------------
   `SVTEST(test_udp_port_filtering_port0_ingress)
   `INFO("test_udp_port_filtering: Filter UDP packets on dst port. Ingress In0, UDP port 10 and UDP port 13 go to Out2(PL), everything else to Out1(PS)");
   fork
      begin : load_stimulus_port0
         //
         UDPPacket test_packet;
         //
         @(negedge clk);
         // Load sensible CSR values
         csr_classifier0_mac <= {8'd0,8'd6,8'd7,8'd8,8'd9,8'd10};
         csr_classifier0_ip <= {8'd5,8'd6,8'd7,8'd8};
         csr_classifier0_udp0 <= 'd10;
         csr_classifier0_udp1 <= 'd13;
         csr_classifier0_udp0_enable <= 1'b1;
         csr_classifier0_udp1_enable <= 1'b1;
         csr_classifier0_expose_drat <= 1'b0;
         @(negedge clk);
         csr_classifier0_enable <= 1'b1;

         // Open valve to isolate UUT
         enable_stimulus0 <= 0;
         for (integer i = 0; i < 15; i++) begin
            // Reconstruct (and initialize) packet each iteration
            // Packet size grows 1 octet each time.
            // Need to set TUSER bits appropriately in response to valid octets in
            // last beat like simple_gemac would
            test_packet = UDPPacket::new(i);
            test_packet.add_payload_octet(i[7:0]);
            test_packet.set_udp_src_port(i[15:0]+1);
            test_packet.set_udp_dst_port(i[15:0]);
            test_packet.set_ipv4_src_addr({8'd1,8'd2,8'd3,8'd4});
            test_packet.set_ipv4_dst_addr({8'd5,8'd6,8'd7,8'd8});
            test_packet.set_mac_src({8'd0,8'd1,8'd2,8'd3,8'd4,8'd5});
            test_packet.set_mac_dst({8'd0,8'd6,8'd7,8'd8,8'd9,8'd10});
            // Send to Port0 Ingress
            test_packet.send_udp_to_eth_stream(in0_axis_pre,1);
            // Add bus beats to Golden response FIFO's
            if ((i==10) || (i==13)) begin
               test_packet.send_udp_to_ipv4_stream(out2in0_axis_in_golden,1);
            end else begin
               test_packet.send_udp_to_eth_stream(out1_axis_in_golden,1);
            end
         end // for (integer i = 0; i < 32; i++)
         //
         // Stimulus fully loaded, initialise system for test and release stimulus
         // by opening valve.
         //
         @(negedge clk);
         @(negedge clk);
         // 100% duty cycle on AXIS input bus.
         enable_stimulus0 <= 1'b1;
         // Let response threads run
         ready_to_test <= 1;
         //
         `INFO("test_udp_port_filtering_port0_ingress: Stimulus Done");
         //
      end // block: load_stimulus

      // Response thread for Port1
      begin: read_response_port1
         // Wait until stimulus is loaded.
         while (!ready_to_test) @(posedge clk);
         `INFO("test_udp_port_filtering_port0_ingress: read_response_port1 running");
         // 100% duty cycle on output buses
         enable_response1 <= 1'b1;
         // While golden response FIFO not empty
         while (out1_axis_out_golden.axis.tvalid) begin
            // Pop golden response.
            out1_axis_out_golden.axis.read_beat(golden_beat1,golden_tlast1);
            // Pop response.
            out1_axis_post.axis.read_beat(response_beat1,response_tlast1);
            // Compare response to golden
            `FAIL_UNLESS_EQUAL(golden_beat1,response_beat1);
            `FAIL_UNLESS_EQUAL(golden_tlast1,response_tlast1);
         end // while (out1_axis_golden.axis.tvalid)
         `INFO("test_udp_port_filtering_port0_ingress: read_response_port1 finished");
      end // block: read_response_port1

      // Response thread for port2in0
      begin: read_response_port2in0
         // Wait until stimulus is loaded.
         while (!ready_to_test) @(posedge clk);
         `INFO("test_udp_port_filtering: read_response_port2in0 running");
         // 100% duty cycle on output buses
         enable_response2in0 <= 1'b1;
         // While golden response FIFO not empty
         while (out2in0_axis_out_golden.tvalid) begin
            // Pop golden response.
            out2in0_axis_out_golden.read_beat(golden_beat2in0,golden_tlast2in0);
            // Pop response.
            out2in0_axis_post.read_beat(response_beat2in0,response_tlast2in0);
            // Compare response to golden
            `FAIL_UNLESS_EQUAL(golden_beat2in0,response_beat2in0);
            `FAIL_UNLESS_EQUAL(golden_tlast2in0,response_tlast2in0);
         end // while (out1_axis_golden.tvalid)
         `INFO("test_udp_port_filtering: read_response_port2fom0 finished");
         disable watchdog_thread;
      end // block: read_response_port2in0

      begin : watchdog_thread
         timeout = 500000;
         while(1) begin
            `FAIL_IF(timeout==0);
            timeout = timeout - 1;
            @(posedge clk);
         end
      end // block: watchdog_thread
   join
   `SVTEST_END
   //-------------------------------------------------------------------------------
   //
   //
   //-------------------------------------------------------------------------------
   `SVTEST(test_udp_port_filtering_port1_ingress)
   `INFO("test_udp_port_filtering_port1_ingress: Filter UDP packets on dst port. Ingress In1, UDP port 9 and UDP port 12 go to Out2(PL), everything else to Out0(QSFP)");
   fork
      begin : load_stimulus_port1
         //
         UDPPacket test_packet;
         //
         @(negedge clk);
         // Load sensible CSR values
         csr_classifier1_mac <= {8'd0,8'd6,8'd7,8'd8,8'd9,8'd10};
         csr_classifier1_ip <= {8'd5,8'd6,8'd7,8'd8};
         csr_classifier1_udp0 <= 'd9;
         csr_classifier1_udp1 <= 'd12;
         csr_classifier1_udp0_enable <= 1'b1;
         csr_classifier1_udp1_enable <= 1'b1;
         csr_classifier1_expose_drat <= 1'b0;
         @(negedge clk);
         csr_classifier1_enable <= 1'b1;

         // Open valve to isolate UUT
         enable_stimulus0 <= 0;
         for (integer i = 0; i < 15; i++) begin
            // Reconstruct (and initialize) packet each iteration
            // Packet size grows 1 octet each time.
            // Need to set TUSER bits appropriately in response to valid octets in
            // last beat like simple_gemac would
            test_packet = UDPPacket::new(i);
            test_packet.add_payload_octet(i[7:0]);
            test_packet.set_udp_src_port(i[15:0]+1);
            test_packet.set_udp_dst_port(i[15:0]);
            test_packet.set_ipv4_src_addr({8'd1,8'd2,8'd3,8'd4});
            test_packet.set_ipv4_dst_addr({8'd5,8'd6,8'd7,8'd8});
            test_packet.set_mac_src({8'd0,8'd1,8'd2,8'd3,8'd4,8'd5});
            test_packet.set_mac_dst({8'd0,8'd6,8'd7,8'd8,8'd9,8'd10});
            // Send to Port0 Ingress
            test_packet.send_udp_to_eth_stream(in1_axis_pre,1);
            // Add bus beats to Golden response FIFO's
            if ((i==9) || (i==12)) begin
               test_packet.send_udp_to_ipv4_stream(out2in1_axis_in_golden,1);
            end else begin
               test_packet.send_udp_to_eth_stream(out0_axis_in_golden,1);
            end
         end // for (integer i = 0; i < 32; i++)
         //
         // Stimulus fully loaded, initialise system for test and release stimulus
         // by opening valve.
         //
         @(negedge clk);
         @(negedge clk);
         // 100% duty cycle on AXIS input bus.
         enable_stimulus1 <= 1'b1;
         // Let response threads run
         ready_to_test <= 1;
         //
         `INFO("test_udp_port_filtering_port1_ingress: Stimulus Done");
         //
      end // block: load_stimulus

      // Response thread for Port0
      begin: read_response_port0
         // Wait until stimulus is loaded.
         while (!ready_to_test) @(posedge clk);
         `INFO("test_udp_port_filtering: read_response_port1 running");
         // 100% duty cycle on output buses
         enable_response0 <= 1'b1;
         // While golden response FIFO not empty
         while (out1_axis_out_golden.axis.tvalid) begin
            // Pop golden response.
            out1_axis_out_golden.axis.read_beat(golden_beat1,golden_tlast1);
            // Pop response.
            out1_axis_post.axis.read_beat(response_beat1,response_tlast1);
            // Compare response to golden
            `FAIL_UNLESS_EQUAL(golden_beat1,response_beat1);
            `FAIL_UNLESS_EQUAL(golden_tlast1,response_tlast1);
         end // while (out1_axis_golden.axis.tvalid)
         `INFO("test_udp_port_filtering_port1_ingress: read_response_port1 finished");
      end // block: read_response_port1

      // Response thread for port2in1
      begin: read_response_port2in1
         // Wait until stimulus is loaded.
         while (!ready_to_test) @(posedge clk);
         `INFO("test_udp_port_filtering: read_response_port2in1 running");
         // 100% duty cycle on output buses
         enable_response2in1 <= 1'b1;
         // While golden response FIFO not empty
         while (out2in1_axis_out_golden.tvalid) begin
            // Pop golden response.
            out2in1_axis_out_golden.read_beat(golden_beat2in1,golden_tlast2in1);
            // Pop response.
            out2in1_axis_post.read_beat(response_beat2in1,response_tlast2in1);
            // Compare response to golden
            `FAIL_UNLESS_EQUAL(golden_beat2in1,response_beat2in1);
            `FAIL_UNLESS_EQUAL(golden_tlast2in1,response_tlast2in1);
         end // while (out1_axis_golden.tvalid)
         `INFO("test_udp_port_filtering_port1_ingress: read_response_port2fom1 finished");
         disable watchdog_thread;
      end // block: read_response_port2in1

      begin : watchdog_thread
         timeout = 500000;
         while(1) begin
            `FAIL_IF(timeout==0);
            timeout = timeout - 1;
            @(posedge clk);
         end
      end // block: watchdog_thread
   join
   `SVTEST_END
   //-------------------------------------------------------------------------------
   //
   //
   //-------------------------------------------------------------------------------
   `SVTEST(test_udp_port_filtering_port2out0_ingress)
   `INFO("test_udp_port_filtering_port2out0_ingress: Frame DRaT packets to Out0(QSFP)");
   fork
      begin : load_stimulus_port2to0
         //

         UDPPacket response_packet;
         DRaTPacket test_packet;
         //
         @(negedge clk);
         // Load sensible CSR values
         csr_framer0_mac_src <=  TEST_MAC_SRC;
         csr_framer0_mac_dst <=  TEST_MAC_DST;
         csr_framer0_ipv4_dst <= TEST_IPV4_DST;
         csr_framer0_ipv4_src <= TEST_IPV4_SRC;
         csr_framer0_udp_src <= 16'h2000;
         csr_framer0_udp_dst0 <= 16'h1000;
         csr_framer0_udp_dst1 <= 16'h1001;
         csr_framer0_udp_dst2 <= 16'h1002;
         csr_framer0_udp_dst3 <= 16'h1003;
         csr_framer0_udp_dst4 <= 16'h1004;
         csr_framer0_udp_dst5 <= 16'h1005;
         csr_framer0_udp_dst6 <= 16'h1006;
         csr_framer0_udp_dst7 <= 16'h1007;
         @(negedge clk);
         csr_framer0_enable <= 1'b1;
         // Open valve to isolate UUT
         enable_stimulus2to0 <= 0;
         // Generate 16 test packets
         for (integer i = 0; i < 16; i++) begin
            // Constuct a DRaT payload to be framed by the DUT
            // Frame a reference Eth+IPv4+UDP encapsulation as a golden reference
            test_packet = DRaTPacket::new();
            response_packet = UDPPacket::new(drat_protocol::beats_to_bytes(TEST_DRAT_SIZE));
            // Eth+IPv4+UDP headers:
            // Create packets that increment the UDP dest port to match the FlowID decoding.
            response_packet.set_udp_src_port(16'h2000);
            response_packet.set_udp_dst_port(i[2:0] | 16'h1000);
            response_packet.set_ipv4_src_addr(TEST_IPV4_SRC);
            response_packet.set_ipv4_dst_addr(TEST_IPV4_DST);
            response_packet.set_mac_src(TEST_MAC_SRC);
            response_packet.set_mac_dst(TEST_MAC_DST);
            response_packet.calculate_ipv4_checksum();
            // DRaT headers:
            test_packet.set_flow_id(32'h0 | i[2:0]);
            test_packet.set_timestamp(i);
            // DRaT payload:
            test_packet.set_length(drat_protocol::beats_to_bytes(TEST_DRAT_SIZE));
            // Generate ramped payload.
            test_packet.ramp;
            test_packet.rewind_payload;
            // Get 2 DRaT header beats and write to stimulus and golden ref
            in2out0_axis_pre.axis.write_beat(test_packet.get_raw_header,1'b0);
            response_packet.set_payload_8octets(test_packet.get_raw_header);
            in2out0_axis_pre.axis.write_beat(test_packet.get_timestamp,1'b0);
            response_packet.set_payload_8octets(test_packet.get_timestamp);
	    // Get 13 64b payload beats and pack them into the stimulus FIFO and golden ref
            for (int x = 0 ; x < TEST_DRAT_SIZE - 3 ; x = x + 1)
	      begin
                 beat_in = test_packet.get_beat;
                 in2out0_axis_pre.axis.write_beat(beat_in,1'b0);
                 response_packet.set_payload_8octets(beat_in);
              end
            // Set TLAST on the last payload beat.
            beat_in = test_packet.get_beat;
            in2out0_axis_pre.axis.write_beat(beat_in,1'b1);
            response_packet.set_payload_8octets(beat_in);
            response_packet.send_udp_to_eth_stream(out0_axis_in_golden,0);
         end // for (integer i = 0; i < 15; i++)
         //
         // Stimulus fully loaded, initialise system for test and release stimulus
         // by opening valve.
         //
         @(negedge clk);
         @(negedge clk);
         // 100% duty cycle on AXIS input bus.
         enable_stimulus2to0 <= 1'b1;
         // Let response threads run
         ready_to_test <= 1;
         //
         `INFO("test_udp_port_filtering_port2out0_ingress: Stimulus Done");
         //
      end // block: load_stimulus_port2to0

      // Response thread for port0
      begin: read_response_port0
         // Wait until stimulus is loaded.
         while (!ready_to_test) @(posedge clk);
         `INFO("test_eth_ipv4_udp_framing: read_response_port0 running");
         // 100% duty cycle on output buses
         enable_response0 <= 1'b1;
         // While golden response FIFO not empty
         while (out0_axis_out_golden.axis.tvalid) begin
            // Pop golden response.
            out0_axis_out_golden.axis.read_beat(golden_beat0,golden_tlast0);
            // Pop response.
            out0_axis_post.axis.read_beat(response_beat0,response_tlast0);
            // Compare response to golden
            `FAIL_UNLESS_EQUAL(golden_beat0,response_beat0);
            `FAIL_UNLESS_EQUAL(golden_tlast0,response_tlast0);
         end // while (out1_axis_golden.axis.tvalid)
         `INFO("test_udp_port_filtering_port2out0_ingress: read_response_port0 finished");
         disable watchdog_thread;
      end // block: read_response_port0

      begin : watchdog_thread
         timeout = 500000;
         while(1) begin
            `FAIL_IF(timeout==0);
            timeout = timeout - 1;
            @(posedge clk);
         end
      end // block: watchdog_thread
   join
  `SVTEST_END


  `SVUNIT_TESTS_END


    task idle_all();
       in0_axis_pre.axis.idle_master();
       in1_axis_pre.axis.idle_master();
       in2out0_axis_pre.axis.idle_master();
       in2out1_axis_pre.axis.idle_master();

       out0_axis_post.axis.idle_slave();
       out1_axis_post.axis.idle_slave();
       out2in0_axis_post.idle_slave();
       out2in1_axis_post.idle_slave();

       out0_axis_in_golden.axis.idle_master();
       out1_axis_in_golden.axis.idle_master();
       out2in0_axis_in_golden.idle_master();
       out2in1_axis_in_golden.idle_master();

       out0_axis_out_golden.axis.idle_slave();
       out1_axis_out_golden.axis.idle_slave();
       out2in0_axis_out_golden.idle_slave();
       out2in1_axis_out_golden.idle_slave();

    endtask // idle_all

endmodule // eth_classifier_2_egress_unit_test
