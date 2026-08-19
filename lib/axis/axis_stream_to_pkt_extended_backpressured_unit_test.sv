//-----------------------------------------------------------------------------
// File:    axis_stream_to_pkt_extended_backpressured_unit_test.sv
// 
// Author: Daniel Sanei, FPGA Engineer
//
// Description:
// Unit tests for RX MIMO output framer with extended DRaT packets. Built upon
// axis_stream_to_pkt_backpressured.sv as a baseline.
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

`include "svunit_defines.svh"
`include "drat_protocol.sv"

`include "axis_stream_to_pkt_extended_backpressured.sv"

module axis_stream_to_pkt_extended_backpressured_unit_test;
   timeunit 1ns;
   timeprecision 1ps;
   import drat_protocol::*;
   import svunit_pkg::svunit_testcase;

   string name = "axis_stream_to_pkt_extended_ut";
   svunit_testcase svunit_ut;


   //=========================================================================
   // Constants
   //=========================================================================
   localparam TIME_FIFO_SIZE = 4;
   localparam SAMPLE_FIFO_SIZE = 13;
   localparam PACKET_FIFO_SIZE = 8;
   localparam IQ_WIDTH = 16;
   localparam TIME_PER_PKT_WIDTH = 16;
   localparam bit USE_ULTRA = 0;

   localparam logic [63:0] TEST_START_TIME = 64'h0000_0000_1000_0000;
   localparam logic [31:0] TEST_FLOW_ID = 32'h1234_ABCD;
   localparam logic [63:0] TEST_METADATA = 64'h1A2B_3C4D_5E6F_0000;
   localparam logic [63:0] TEST_METADATA_2 = 64'hBEEF_0123_4567_89AB;

   localparam logic [13:0] TEST_PACKET_SIZE = 14'd4;
   localparam logic [15:0] TEST_TIME_PER_PKT = 16'd4;


   //=========================================================================
   // Clock
   //=========================================================================

   logic clk;

   initial begin
      clk <= 1'b0;
   end
   always begin
      #5 clk <= ~clk;
   end


   //=========================================================================
   // DUT control/status signals
   //=========================================================================
   logic rst;
   // Control signals
   logic enable;
   logic [63:0] start_time; // Write this register with start time to annotate into bursts first packet.
   logic [13:0] packet_size; // Packet size expressed in number of samples
   logic [31:0] flow_id; // DRaT Flow ID for this flow (union of src + dst)
   logic [15:0] time_per_pkt; // Time increment per packet of size packet_size
   logic [47:0] burst_size; // Number of samples in a burst. Write to zero for infinite burst.
   logic [63:0] rx_mimo_metadata; // Contains peak detect (timestamp), fractional delay estimate, phase estimate.
   logic has_metadata; // Checks if packet contains metadata (control logic for legacy vs. extended packets)
   logic  abort; // Assert this signal for a single cycle to trigger an async return to idle.
   // Status Flags
   logic idle; // Assert when state machine is idle


   //=========================================================================
   // Packet stream interface
   //=========================================================================
   axis_t #(.WIDTH(32)) axis_stream_in(.clk(clk)); // complex 32-bit IQ samples
   axis_t #(.WIDTH(64)) axis_pkt_out(.clk(clk));   // 64-bit beats


   //=========================================================================
   // Instantiate DUT
   //=========================================================================
   axis_stream_to_pkt_extended_backpressured
     #(
       .TIME_FIFO_SIZE(TIME_FIFO_SIZE),
       .SAMPLE_FIFO_SIZE(SAMPLE_FIFO_SIZE),
       .PACKET_FIFO_SIZE(PACKET_FIFO_SIZE),
       .IQ_WIDTH(IQ_WIDTH),
       .USE_ULTRA(USE_ULTRA))
   output_framer_dut
       (
       .clk(clk),
       .rst(rst),
       .enable(enable),
       .start_time(start_time),
       .packet_size(packet_size),
       .flow_id(flow_id),
       .time_per_pkt(time_per_pkt),
       .burst_size(burst_size),
       .rx_mimo_metadata(rx_mimo_metadata),
       .has_metadata(has_metadata),
       .abort(abort),
       .idle(idle),
       .axis_stream(axis_stream_in),
       .axis_pkt(axis_pkt_out)
       );


   //=========================================================================
   // Build
   //=========================================================================
   function void build();
      svunit_ut = new(name);
   endfunction


   //=========================================================================
   // Setup for running unit tests
   //=========================================================================
   task setup();
      svunit_ut.setup();

      rst <= 1'b1;
      enable <= '0;
      start_time <= '0;
      packet_size <= '0;
      flow_id <= '0;
      time_per_pkt <= '0;
      burst_size <= '0;
      rx_mimo_metadata <= '0;
      has_metadata <= 0;
      abort <= 1'b0;
      // idle <= 1'b0;

      axis_stream_in.tdata <= '0;
      axis_stream_in.tvalid <= 1'b0;
      axis_stream_in.tlast <= 1'b0;

      axis_pkt_out.tready <= 1'b0;

      @(negedge clk);
      rst <= 1'b0;
      @(negedge clk);

   endtask


   //=========================================================================
   // Reset after unit tests are complete
   //=========================================================================
   task teardown();
      svunit_ut.teardown();
   endtask


   //=========================================================================
   // Unit tests
   //=========================================================================
   `SVUNIT_TESTS_BEGIN

   //=========================================================================
   // Essential test cases
   //=========================================================================
   // Input state machine run control
   //-------------------------------------------------------------------------
   `SVTEST(enable_run_control)
      rst <= 1'b1;
      enable <= 1'b0;
      @(negedge clk);

      `FAIL_UNLESS_EQUAL(axis_stream_in.tready, 1'b0);
      `FAIL_UNLESS_EQUAL(axis_pkt_out.tvalid, 1'b0);
      `FAIL_UNLESS_EQUAL(idle, 1'b1);

      @(negedge clk);
      rst <= 1'b0;
      @(negedge clk);

      `FAIL_UNLESS_EQUAL(axis_stream_in.tready, 1'b0);
      `FAIL_UNLESS_EQUAL(axis_pkt_out.tvalid, 1'b0);
      `FAIL_UNLESS_EQUAL(idle, 1'b1);

      @(negedge clk);
      enable <= 1'b1;
      @(negedge clk);

      `FAIL_UNLESS_EQUAL(axis_stream_in.tready, 1'b1);
      `FAIL_UNLESS_EQUAL(axis_pkt_out.tvalid, 1'b0);
      `FAIL_UNLESS_EQUAL(idle, 1'b0);
      
   `SVTEST_END

   //-------------------------------------------------------------------------
   // Single burst with 1 extended packet (4 complex samples)
   //-------------------------------------------------------------------------
   `SVTEST(single_extended_packet_burst)
      logic [31:0] sample_0 = 32'hA001_A002;
      logic [31:0] sample_1 = 32'h003B_004B;
      logic [31:0] sample_2 = 32'h05C0_06C0;
      logic [31:0] sample_3 = 32'h7D00_8D00;

      logic [63:0] observed_data [0:4];
      logic observed_tlast [0:4];

      logic [63:0] expected_header;
      expected_header = {INT16_COMPLEX_EXTENDED_EOB, 8'h00, 16'd40, TEST_FLOW_ID};
      @(negedge clk);

      // $display("output framer tfifo tdata 1 = %h", output_framer_dut.tfifo_tdata);
      
      // $display("output framer pfifo tdata 1 = %h", output_framer_dut.axis_pfifo.tdata);

      // configure DUT
      start_time <= TEST_START_TIME;
      packet_size <= TEST_PACKET_SIZE;
      flow_id <= TEST_FLOW_ID;
      time_per_pkt <= TEST_TIME_PER_PKT;
      burst_size <= 48'd4;
      rx_mimo_metadata <= TEST_METADATA;
      has_metadata <= 1;
      
      //axis_pkt_out.tready <= 1'b0;  // artificial backpressure on pfifo (to read results)
      @(negedge clk);

      // enable packetizer
      enable <= 1'b1;
      @(negedge clk);

      // write (stream) IQ samples
      axis_stream_in.write_beat(sample_0, 1'b0);
      axis_stream_in.write_beat(sample_1, 1'b0);
      axis_stream_in.write_beat(sample_2, 1'b0);
      axis_stream_in.write_beat(sample_3, 1'b0);
      @(negedge clk);

      // read results from pfifo ==> raw header, timestamp, metadata, 2 payload beats
      axis_pkt_out.read_beat(observed_data[0], observed_tlast[0]);
      axis_pkt_out.read_beat(observed_data[1], observed_tlast[1]);
      axis_pkt_out.read_beat(observed_data[2], observed_tlast[2]);
      axis_pkt_out.read_beat(observed_data[3], observed_tlast[3]);
      axis_pkt_out.read_beat(observed_data[4], observed_tlast[4]);
      @(negedge clk);

      $display("Observed header 2 = %h", observed_data[0]);
      $display("Expected header 2 = %h", expected_header);

      // check output framer results vs expected
      `FAIL_UNLESS_EQUAL(observed_data[0], expected_header);
      `FAIL_UNLESS_EQUAL(observed_tlast[0], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[1], TEST_START_TIME);
      `FAIL_UNLESS_EQUAL(observed_tlast[1], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[2], TEST_METADATA);
      `FAIL_UNLESS_EQUAL(observed_tlast[2], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[3], {sample_0, sample_1});
      `FAIL_UNLESS_EQUAL(observed_tlast[3], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[4], {sample_2, sample_3});
      `FAIL_UNLESS_EQUAL(observed_tlast[4], 1'b1);

   `SVTEST_END

   //-------------------------------------------------------------------------
   // Single burst with 2 extended packet (8 complex samples)
   //-------------------------------------------------------------------------
   `SVTEST(two_extended_packets_burst)
      logic [31:0] sample_0 = 32'hA001_A002;
      logic [31:0] sample_1 = 32'h003B_004B;
      logic [31:0] sample_2 = 32'h05C0_06C0;
      logic [31:0] sample_3 = 32'h7D00_8D00;
      logic [31:0] sample_4 = 32'h1000_2000;
      logic [31:0] sample_5 = 32'h3000_4000;
      logic [31:0] sample_6 = 32'hF000_D000;
      logic [31:0] sample_7 = 32'hC000_B000;

      logic [63:0] observed_data [0:9];
      logic observed_tlast [0:9];

      logic [63:0] expected_header_1;
      logic [63:0] expected_header_2;
      expected_header_1 = {INT16_COMPLEX_EXTENDED, 8'h00, 16'd40, TEST_FLOW_ID};
      expected_header_2 = {INT16_COMPLEX_EXTENDED_EOB, 8'h01, 16'd40, TEST_FLOW_ID};
      @(negedge clk);;

      // configure DUT
      start_time <= TEST_START_TIME;
      packet_size <= TEST_PACKET_SIZE;
      flow_id <= TEST_FLOW_ID;
      time_per_pkt <= TEST_TIME_PER_PKT;
      burst_size <= 48'd8;
      rx_mimo_metadata <= TEST_METADATA;
      has_metadata <= 1;
      
      //axis_pkt_out.tready <= 1'b0;  // artificial backpressure on pfifo (to read results)
      @(negedge clk);

      // enable packetizer
      enable <= 1'b1;
      @(negedge clk);

      // write (stream) IQ samples
      axis_stream_in.write_beat(sample_0, 1'b0);
      axis_stream_in.write_beat(sample_1, 1'b0);
      axis_stream_in.write_beat(sample_2, 1'b0);
      axis_stream_in.write_beat(sample_3, 1'b0);
      axis_stream_in.write_beat(sample_4, 1'b0);
      axis_stream_in.write_beat(sample_5, 1'b0);
      axis_stream_in.write_beat(sample_6, 1'b0);
      axis_stream_in.write_beat(sample_7, 1'b0);
      @(negedge clk);

      // read results from pfifo ==> raw header, timestamp, metadata, 2 payload beats
      for ( int i = 0; i < 10; i++ ) begin
         axis_pkt_out.read_beat(observed_data[i], observed_tlast[i]);
      end
      @(negedge clk);

      $display("Packet 1:");
      $display("  Observed header = %h", observed_data[0]);
      $display("  Expected header = %h", expected_header_1);
      $display("  Observed time   = %h", observed_data[1]);
      $display("  Expected time   = %h", TEST_START_TIME);
      $display("  Observed meta   = %h", observed_data[2]);
      $display("  Expected meta   = %h", TEST_METADATA);

      $display("Packet 2:");
      $display("  Observed header = %h", observed_data[5]);
      $display("  Expected header = %h", expected_header_2);
      $display("  Observed time   = %h", observed_data[6]);
      $display("  Expected time   = %h", TEST_START_TIME + TEST_TIME_PER_PKT);
      $display("  Observed meta   = %h", observed_data[7]);
      $display("  Expected meta   = %h", TEST_METADATA);

      // check output framer results vs expected
      `FAIL_UNLESS_EQUAL(observed_data[0], expected_header_1);
      `FAIL_UNLESS_EQUAL(observed_tlast[0], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[1], TEST_START_TIME);
      `FAIL_UNLESS_EQUAL(observed_tlast[1], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[2], TEST_METADATA);
      `FAIL_UNLESS_EQUAL(observed_tlast[2], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[3], {sample_0, sample_1});
      `FAIL_UNLESS_EQUAL(observed_tlast[3], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[4], {sample_2, sample_3});
      `FAIL_UNLESS_EQUAL(observed_tlast[4], 1'b1);

      `FAIL_UNLESS_EQUAL(observed_data[5], expected_header_2);
      `FAIL_UNLESS_EQUAL(observed_tlast[5], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[6], TEST_START_TIME + TEST_TIME_PER_PKT);
      `FAIL_UNLESS_EQUAL(observed_tlast[6], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[7], TEST_METADATA);
      `FAIL_UNLESS_EQUAL(observed_tlast[7], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[8], {sample_4, sample_5});
      `FAIL_UNLESS_EQUAL(observed_tlast[8], 1'b0);
      `FAIL_UNLESS_EQUAL(observed_data[9], {sample_6, sample_7});
      `FAIL_UNLESS_EQUAL(observed_tlast[9], 1'b1);

   `SVTEST_END

   //-------------------------------------------------------------------------
   // Interleaving packet types (with and without RX MIMO metadata)
   //    --> EXTENDED --> LEGACY --> EXTENDED
   // - packet_size = 4, burst_size = 12
   // - extended packets = header, timestamp, metadata, 2 samples --> 5 beats
   // - legacy packets = header, timestamp, 2 samples --> 4 beats
   //    - total = extended, legacy, extended_EOB --> 5 + 4 + 5 = 14 beats
   //-------------------------------------------------------------------------
   `SVTEST(interleaving_extended_start)
      logic [31:0] sample [0:11];
      
      logic [63:0] observed [0:13];
      logic observed_tlast [0:13];

      logic [63:0] expected [0:13];
      logic expected_tlast [0:13];

      for (int i = 0; i < 12; i++) begin
         sample[i] = 32'hA000_0000 + i;
      end
      @(negedge clk);

      // configure DUT
      start_time <= TEST_START_TIME;
      packet_size <= TEST_PACKET_SIZE;
      flow_id <= TEST_FLOW_ID;
      time_per_pkt <= TEST_TIME_PER_PKT;
      burst_size <= 48'd12;
      rx_mimo_metadata <= TEST_METADATA;
      has_metadata <= 1;
      @(negedge clk);

      // enable packetizer
      enable <= 1'b1;
      @(negedge clk);

      // packet 0 (extended)
      has_metadata <= 1'b1;
      rx_mimo_metadata <= TEST_METADATA;
      for (int i = 0; i < 4; i++) begin
         axis_stream_in.write_beat(sample[i], 1'b0);
      end
      @(negedge clk);

      // packet 1 (legacy)
      has_metadata <= 1'b0;
      rx_mimo_metadata <= '0;
      for (int i = 4; i < 8; i++) begin
         axis_stream_in.write_beat(sample[i], 1'b0);
      end
      @(negedge clk);

      // packet 2 (extended)
      has_metadata <= 1'b1;
      rx_mimo_metadata <= TEST_METADATA_2;
      for (int i = 8; i < 12; i++) begin
         axis_stream_in.write_beat(sample[i], 1'b0);
      end
      @(negedge clk);

      // set expected results
      expected[0]  = {INT16_COMPLEX_EXTENDED, 8'h00, 16'd40, TEST_FLOW_ID};
      expected[1]  = TEST_START_TIME;
      expected[2]  = TEST_METADATA;
      expected[3]  = {sample[0], sample[1]};
      expected[4]  = {sample[2], sample[3]};

      expected[5]  = {INT16_COMPLEX, 8'h01, 16'd32, TEST_FLOW_ID};
      expected[6]  = TEST_START_TIME + 4;
      expected[7]  = {sample[4], sample[5]};
      expected[8]  = {sample[6], sample[7]};

      expected[9]  = {INT16_COMPLEX_EXTENDED_EOB, 8'h02, 16'd40, TEST_FLOW_ID};
      expected[10] = TEST_START_TIME + 8;
      expected[11] = TEST_METADATA_2;
      expected[12] = {sample[8], sample[9]};
      expected[13] = {sample[10], sample[11]};

      for (int i = 0; i < 14; i++) begin
         expected_tlast[i] = 1'b0;
      end
      expected_tlast[4]  = 1'b1;
      expected_tlast[8]  = 1'b1;
      expected_tlast[13] = 1'b1;

      // check output framer results vs expected
      for (int i = 0; i < 14; i++) begin
         axis_pkt_out.read_beat(observed[i], observed_tlast[i]);
         `FAIL_UNLESS_EQUAL(observed[i], expected[i]);
         `FAIL_UNLESS_EQUAL(observed_tlast[i], expected_tlast[i]);
      end

   `SVTEST_END

   //-------------------------------------------------------------------------
   // Interleaving packet types (with and without RX MIMO metadata)
   //    --> LEGACY --> EXTENDED --> LEGACY
   // - packet_size = 4, burst_size = 12
   // - extended packets = header, timestamp, metadata, 2 samples --> 5 beats
   // - legacy packets = header, timestamp, 2 samples --> 4 beats
   //    - total = legacy, extended, legacy_EOB --> 4 + 5 + 4 = 13 beats
   //-------------------------------------------------------------------------
   `SVTEST(interleaving_legacy_start)
      logic [31:0] sample [0:11];
      
      logic [63:0] observed [0:12];
      logic observed_tlast [0:12];

      logic [63:0] expected [0:12];
      logic expected_tlast [0:12];

      for (int i = 0; i < 12; i++) begin
         sample[i] = 32'hA000_0000 + i;
      end
      @(negedge clk);

      // configure DUT
      start_time <= TEST_START_TIME;
      packet_size <= TEST_PACKET_SIZE;
      flow_id <= TEST_FLOW_ID;
      time_per_pkt <= TEST_TIME_PER_PKT;
      burst_size <= 48'd12;
      rx_mimo_metadata <= '0;
      has_metadata <= 0;
      @(negedge clk);

      // enable packetizer
      enable <= 1'b1;
      @(negedge clk);

      // packet 0 (legacy)
      has_metadata <= 1'b0;
      rx_mimo_metadata <= '0;
      for (int i = 0; i < 4; i++) begin
         axis_stream_in.write_beat(sample[i], 1'b0);
      end
      @(negedge clk);

      // packet 1 (extended)
      has_metadata <= 1'b1;
      rx_mimo_metadata <= TEST_METADATA;
      for (int i = 4; i < 8; i++) begin
         axis_stream_in.write_beat(sample[i], 1'b0);
      end
      @(negedge clk);

      // packet 2 (legacy)
      has_metadata <= 1'b0;
      rx_mimo_metadata <= '0;
      for (int i = 8; i < 12; i++) begin
         axis_stream_in.write_beat(sample[i], 1'b0);
      end
      @(negedge clk);

      // set expected results
      expected[0]  = {INT16_COMPLEX, 8'h00, 16'd32, TEST_FLOW_ID};
      expected[1]  = TEST_START_TIME;
      expected[2]  = {sample[0], sample[1]};
      expected[3]  = {sample[2], sample[3]};

      expected[4]  = {INT16_COMPLEX_EXTENDED, 8'h01, 16'd40, TEST_FLOW_ID};
      expected[5]  = TEST_START_TIME + 4;
      expected[6]  = TEST_METADATA;
      expected[7]  = {sample[4], sample[5]};
      expected[8]  = {sample[6], sample[7]};

      expected[9]  = {INT16_COMPLEX_EOB, 8'h02, 16'd32, TEST_FLOW_ID};
      expected[10] = TEST_START_TIME + 8;
      expected[11] = {sample[8], sample[9]};
      expected[12] = {sample[10], sample[11]};

      for (int i = 0; i < 13; i++) begin
         expected_tlast[i] = 1'b0;
      end
      expected_tlast[3]  = 1'b1;
      expected_tlast[8]  = 1'b1;
      expected_tlast[12] = 1'b1;

      // check output framer results vs expected
      for (int i = 0; i < 13; i++) begin
         axis_pkt_out.read_beat(observed[i], observed_tlast[i]);
         `FAIL_UNLESS_EQUAL(observed[i], expected[i]);
         `FAIL_UNLESS_EQUAL(observed_tlast[i], expected_tlast[i]);
      end

   `SVTEST_END

   `SVUNIT_TESTS_END

endmodule
