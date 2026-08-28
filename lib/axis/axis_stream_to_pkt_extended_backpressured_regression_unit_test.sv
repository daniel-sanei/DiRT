//-------------------------------------------------------------------------------
// File:    axis_stream_to_pkt_extended_backpressured_regression_unit_test.sv
//
// Author:  Ian Buckley, Ion Concepts LLC
// 
// Edited by: Daniel Sanei, FPGA Engineer
//
// Description:
// Unit tests for axis_stream_to_pkt_extended_backpressured (legacy regression only)
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-------------------------------------------------------------------------------

`include "svunit_defines.svh"
`include "drat_protocol.sv"

module axis_stream_to_pkt_extended_backpressured_regression_unit_test;
   timeunit 1ns;
   timeprecision 1ps;

   import drat_protocol::*;
   import svunit_pkg::svunit_testcase;
   string name = "axis_stream_to_pkt_ut";
   svunit_testcase svunit_ut;

   localparam SIZE_STIM=10;
   localparam SIZE_RESP=11;
   localparam TEST_RXMIMO_METADATA=64'h0101_A2B3_9999_FFFF;

   logic  clk;
   logic  rst;

   // Pre-Buffer Input Bus
   axis_t #(.WIDTH(32)) axis_stimulus_pre(.clk(clk));
   // Bus between stimulus buffer and valve
   axis_t #(.WIDTH(32)) axis_stimulus_post(.clk(clk));
   // Bus between stimulus valve and UUT
   axis_t #(.WIDTH(32)) axis_stimulus_gated(.clk(clk));

   // DUT Output bus
   pkt_stream_extended_t axis_response_gated(.clk(clk));
   // Bus between response vavle and buffer
   pkt_stream_extended_t axis_response_pre(.clk(clk));
   // Post Buffer Output bus
   pkt_stream_extended_t axis_response_post(.clk(clk));


   logic  enable;
   // Write this register with start time to annotate into bursts first packet.
   logic [63:0] start_time;
   // Packet size expressed in number of samples
   logic [13:0] packet_size;
   // DRaT Flow ID for this flow (union of src + dst)
   logic [31:0] flow_id;
   // Time increment per packet of size packet_size
   logic [15:0] time_per_pkt;
   // Number of samples in a burst. Write to zero for infinite burst.
   logic [47:0] burst_size;
   // Contains peak detect (timestamp), fractional delay estimate, phase estimate.
   logic [63:0] rx_mimo_metadata;
   // Checks if packet contains metadata (control logic for legacy vs. extended packets)
   logic has_metadata;
   // Assert this signal for a single cycle to trigger an async return to idle.
   logic        abort;

   // Declarations for Stimulus Thread(s)
   logic        enable_stimulus;
   logic        enable_response;
   logic        ready_to_test;
   // Declarations for Response Thread(s)
   DRaTPacketExtended golden_packet, response_packet;
   // Watchdog
   int 		timeout;

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
   // Buffer input sample stream
   // FIFO is 32 bits wide for one complex 16b sample per clock.
   //-------------------------------------------------------------------------------
   // Unused FIFO ports
   wire [SIZE_STIM:0] space_stim, occupied_stim;

   axis_fifo_wrapper  #(
                        .SIZE(SIZE_STIM)
                        )
   axis_fifo_stimulus_i (
                         .clk(clk),
                         .rst(rst),
                         .in_axis(axis_stimulus_pre),
                         .out_axis(axis_stimulus_post),
                         //-- Current fullness of FIFO
                         .space(space_stim),
                         .occupied(occupied_stim)
                         );



   axis_valve axis_valve_stimulus_i (
                                     .clk(clk),
                                     .rst(rst),
                                     .in_axis(axis_stimulus_post),
                                     .out_axis(axis_stimulus_gated),
                                     .enable(enable_stimulus)
                                     );

   //===================================
   // This is the UUT that we're
   // running the Unit Tests on
   //===================================

   axis_stream_to_pkt_backpressured
     #(
       .TIME_FIFO_SIZE(4),
       .SAMPLE_FIFO_SIZE(13),
       .PACKET_FIFO_SIZE(8),
       .IQ_WIDTH(16)
       )
   my_axis_stream_to_pkt_extended_backpressured
     (
      .clk(clk),
      .rst(rst),
      //-------------------------------------------------------------------------------
      // CSR registers
      //-------------------------------------------------------------------------------
      .enable(enable),
      .start_time(start_time),
      .packet_size(packet_size), // Packet size expressed in 64bit words including headers
      .flow_id(flow_id), // DRaT Flow ID for this flow (union of src + dst)
      .time_per_pkt(time_per_pkt),
      .burst_size(burst_size),
      .rx_mimo_metadata(rx_mimo_metadata),
      .has_metadata(has_metadata),
      .abort(abort),
      // Status Flags
      .idle(idle),
      //-------------------------------------------------------------------------------
      // Streaming sample Input Bus
      //-------------------------------------------------------------------------------
      .axis_stream(axis_stimulus_gated),
      //-------------------------------------------------------------------------------
      // AXIS Output Bus
      //-------------------------------------------------------------------------------
      .axis_pkt(axis_response_gated.axis)
      );

   //-------------------------------------------------------------------------------
   // Buffer output response sample stream
   //-------------------------------------------------------------------------------
   axis_valve axis_valve_response_i (
                                     .clk(clk),
                                     .rst(rst),
                                     .in_axis(axis_response_gated.axis),
                                     .out_axis(axis_response_pre.axis),
                                     .enable(enable_response)
                                     );
   // Unused FIFO ports
   wire [SIZE_RESP:0] space_resp,occupied_resp;

   axis_fifo_wrapper  #(
                        .SIZE(SIZE_RESP)
                        )
   axis_fifo_response_i (
                         .clk(clk),
                         .rst(rst),
                         .in_axis(axis_response_pre.axis),
                         .out_axis(axis_response_post.axis),
                         //-- Current fullness of FIFO
                         .space(space_resp),
                         .occupied(occupied_resp)
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

      rst <= 1'b1;
      enable <= 0;
      start_time <= 0; // Write this register with start time to annotate into bursts first packet.
      packet_size <= 0; // Packet size expressed in number of samples
      flow_id <= 0; // DRaT Flow ID for this flow (union of src + dst)
      time_per_pkt <= 0; // Time increment per packet of size packet_size
      burst_size <= 0; // Number of samples in a burst. Write to zero for infinite burst.
      rx_mimo_metadata <= 0;
      has_metadata <= 1'b0;
      abort <= 0; // Assert this signal for a single cycle to trigger an async return to idle.

      // Open all valves by default
      enable_stimulus <= 1'b1;
      enable_response <= 1'b1;
      // Take all bench AXIS buses to a quiescent state
      idle_all();
      // De-assert reset after 10 clock cycles.
      @(posedge clk);
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
     // --EXTENDED--
     // Simple Test. Stream one burst with no throttling.
     //
     // Configured as follows:
     // start_time = 1000
     // packet_size = 10 samples
     // flow_id = {SRC0,DST0}
     // time_per_pkt = 10 (Sample_rate=clk_rate)
     // burst_size = 100 (10 packets)
     // rx_mimo_metadata = arbitrary 64 bits
     // has_metadata = goes high
     //
     //-------------------------------------------------------------------------------
     `SVTEST(burst_10pkts_of_10samples_extended)
   `INFO("One burst of 10 good packets of INT16_COMPLEX_EXTENDED");
   fork
      begin: load_stimulus
         // Setup this test:
         enable <= 0;
         start_time <= 'd1000;
         packet_size <= 'd10;
         flow_id <= {SRC0,DST0};
         time_per_pkt <= 10;
         burst_size <= 100;
         rx_mimo_metadata <= TEST_RXMIMO_METADATA;
         has_metadata <= 1;
         abort <= 0;
         // Response threads can't run until stimulus loaded.
         ready_to_test <= 0;
         // Close valve after stimulus buffer
         enable_stimulus <= 1'b0;
         // Build 100 sample test pattern using ramp
         for (logic [15:0] i = 0; i < 200; i=i+2 ) begin
            axis_stimulus_pre.write_beat({i,i+16'd1},1'b0);
         end


         //
         // Stimulus fully loaded, initialize system for test and release stimulus
         // by opening valve.
         //
         @(negedge clk);
         // Enable configured sub-system operation
         enable <= 1;
         @(negedge clk);
         // 100% duty cycle on AXIS input bus.
         enable_stimulus <= 1'b1;
         // Let response threads run
         ready_to_test <= 1;
         //
         `INFO("one_burst_one_clk_per_samp: Stimulus Done");
         //
      end // block: load_stimulus
      //
      begin: read_response
         //
         // This simulation should produce 10 packets of 10 samples containing a complex ramp waveform.
         // It should all be a single burst and each sample should increment the clock by one.
         //

         // Wait until stimulus is loaded.
         while (!ready_to_test) @(posedge clk);

         // Create Objects
         golden_packet = new;
         response_packet = new;
         // Initialize header fields with default values
         golden_packet.init;
         // Overide FlowID
         golden_packet.set_flow_src(SRC0);
         golden_packet.set_flow_dst(DST0);
         // Set packet length to be header plus 5 beats of 2 complex samples
         golden_packet.set_length(beats_to_bytes(3+5));
         // Set timestamp of first packet to be 1000...
         golden_packet.set_timestamp(1000);
         // Set RX MIMO metadata to arbitrary constant
         golden_packet.set_rx_mimo_metadata(TEST_RXMIMO_METADATA);
         // Explict set packet type to INT16_COMPLEX_EXTENDED
         golden_packet.set_packet_type(INT16_COMPLEX_EXTENDED);
         for (integer i = 0; i < 10; i++) begin
            $display("Extended Packet %d",i);
            // Initialize ramp waveform start value to zero on first pass
            golden_packet.ramp(i===0);
            if (i === 9) begin
               // End of Burst Reached.
               golden_packet.set_packet_type(INT16_COMPLEX_EXTENDED_EOB);
            end
            axis_response_post.pop_pkt(response_packet);
            // (Assert stops implicit void cast warning)
            `FAIL_UNLESS(golden_packet.is_same(response_packet,1'b0));
            // Increment Sequence Number
            golden_packet.inc_seq_id;
            // Increment Packet Time
            golden_packet.set_timestamp(golden_packet.get_timestamp() + 10);
         end // for (integer i = 0; i < 10; i++)

         $display("one_burst_one_clk_per_samp: Good Extended Response");
	 disable watchdog_thread;
      end // block: read_response
      //
      // Watchdog kills simulation if any test case fails to decisively PASS or FAIL.
      //
      begin : watchdog_thread
	 timeout = 10000;
	 while(1) begin
	    `FAIL_IF(timeout==0);
	    timeout = timeout - 1;
	    @(negedge clk);
	 end
      end
   join
   `SVTEST_END
     

     //-------------------------------------------------------------------------------
     // --EXTENDED--
     // Stream one burst with Valid input samples every other clock cycle.
     // Last packet is smaller than max packet size
     // Run input stimulus at 50% duty cycle for 1000 clocks to start.
     //
     // Configured as follows:
     // start_time = 1000
     // packet_size = 10 samples
     // flow_id = {SRC0,DST0}
     // time_per_pkt = 10 (Sample_rate=clk_rate)
     // burst_size = 96 (10 packets)
     // rx_mimo_metadata = arbitrary 64 bits
     // has_metadata = goes high
     //
     //-------------------------------------------------------------------------------
   `SVTEST(burst_10pkts_short_last_extended)
   `INFO("One burst of 10 good packets of INT16_COMPLEX_EXTENDED");
   fork
      begin: load_stimulus
         // Setup this test:
         enable <= 0;
         start_time <= 'd1000;
         packet_size <= 'd10;
         flow_id <= {SRC0,DST0};
         time_per_pkt <= 10;
         burst_size <= 96;
         rx_mimo_metadata <= TEST_RXMIMO_METADATA;
         has_metadata <= 1;
         abort <= 0;
         // Response threads can't run until stimulus loaded.
         ready_to_test <= 0;
         // Close valve after stimulus buffer
         enable_stimulus <= 1'b0;
         // Build 100 sample test pattern using ramp
         for (logic [15:0] i = 0; i < 192; i=i+2 ) begin
            axis_stimulus_pre.write_beat({i,i+16'd1},1'b0);
         end


         //
         // Stimulus fully loaded, initialize system for test and release stimulus
         // by opening valve.
         //
         @(negedge clk);
         // Enable configured sub-system operation
         enable <= 1;
         @(negedge clk);
         // Let response threads run
         ready_to_test <= 1;
         //
         `INFO("one_burst_two_clks_per_samp: Stimulus Done");
         //
         // 1000 clock cycles of 50% duty cycle on AXIS input bus
         // then go 100% duty cycle
         //
         repeat(500) begin
            enable_stimulus <= 1'b0;
            @(negedge clk);
            enable_stimulus <= 1'b1;
            @(negedge clk);
         end
      end // block: load_stimulus
      //
      begin: read_response
         //
         // This simulation should produce 10 packets of 10 samples containing a complex ramp waveform.
         // It should all be a single burst and each sample should increment the clock by one.
         //

         // Wait until stimulus is loaded.
         while (!ready_to_test) @(posedge clk);

         // Create Objects
         golden_packet = new;
         response_packet = new;
         // Initialize header fields with default values
         golden_packet.init;
         // Overide FlowID
         golden_packet.set_flow_src(SRC0);
         golden_packet.set_flow_dst(DST0);
         // Set packet length to be header plus 5 beats of 2 complex samples
         golden_packet.set_length(beats_to_bytes(3+5));
         // Set timestamp of first packet to be 1000...
         golden_packet.set_timestamp(1000);
         // Set RX MIMO metadata to arbitrary constant
         golden_packet.set_rx_mimo_metadata(TEST_RXMIMO_METADATA);
         // Explict set packet type to INT16_COMPLEX_EXTENDED
         golden_packet.set_packet_type(INT16_COMPLEX_EXTENDED);
         for (integer i = 0; i < 10; i++) begin
            $display("Extended Packet %d",i);
            if (i === 9) begin
               // End of Burst Reached.
               golden_packet.set_packet_type(INT16_COMPLEX_EXTENDED_EOB);
               golden_packet.set_length(beats_to_bytes(3+3));
            end
            // Initialize ramp waveform start value to zero on first pass
            golden_packet.ramp(i===0);
            axis_response_post.pop_pkt(response_packet);
            // (Assert stops implicit void cast warning)
            `FAIL_UNLESS(golden_packet.is_same(response_packet,1'b0));
            // Increment Sequence Number
            golden_packet.inc_seq_id;
            // Increment Packet Time
            golden_packet.set_timestamp(golden_packet.get_timestamp() + 10);
         end // for (integer i = 0; i < 10; i++)

         $display("one_burst_two_clks_per_samp: Good Response");
	 disable watchdog_thread;
      end // block: read_response
      //
      // Watchdog kills simulation if any test case fails to decisively PASS or FAIL.
      //
      begin : watchdog_thread
	 timeout = 100000;
	 while(1) begin
	    `FAIL_IF(timeout==0);
	    timeout = timeout - 1;
	    @(negedge clk);
	 end
      end
   join
   `SVTEST_END

     //-------------------------------------------------------------------------------
     // --EXTENDED--
     // Stream two bursts with Valid input samples every other clock cycle.
     // Last packet is smaller than max packet size
     // Run input stimulus at 50% duty cycle for 1000 clocks to start.
     //
     // Configured as follows:
     // start_time = 1000
     // packet_size = 10 samples
     // flow_id = {SRC0,DST0}
     // time_per_pkt = 10 (Sample_rate=clk_rate)
     // burst_size = 94 (10 packets)
     // rx_mimo_metadata = arbitrary 64 bits
     // has_metadata = goes high
     //
     //-------------------------------------------------------------------------------
   `SVTEST(two_bursts_10pkts_short_last_extended)
   `INFO("Two bursts of 10 good packets of INT16_COMPLEX_EXTENDED");
   fork
      begin: load_stimulus
         // Setup this test:
         enable <= 0;
         start_time <= 'd1000;
         packet_size <= 'd10;
         flow_id <= {SRC0,DST0};
         time_per_pkt <= 10;
         burst_size <= 94;
         rx_mimo_metadata <= TEST_RXMIMO_METADATA;
         has_metadata <= 1;
         abort <= 0;
         // Response threads can't run until stimulus loaded.
         ready_to_test <= 0;
         // Close valve after stimulus buffer
         enable_stimulus <= 1'b0;
         // Build 100 sample test pattern using ramp
         for (logic [15:0] i = 0; i < 188*2; i=i+2 ) begin
            axis_stimulus_pre.write_beat({i,i+16'd1},1'b0);
         end


         //
         // Stimulus fully loaded, initialize system for test and release stimulus
         // by opening valve.
         //
         @(negedge clk);
         // Enable configured sub-system operation
         enable <= 1;
         @(negedge clk);
         // Let response threads run
         ready_to_test <= 1;
         //
         `INFO("two_bursts_two_clks_per_samp: Stimulus Done");
         //
         // 1000 clock cycles of 50% duty cycle on AXIS input bus
         // then go 100% duty cycle
         //
         repeat(500) begin
            enable_stimulus <= 1'b0;
            @(negedge clk);
            enable_stimulus <= 1'b1;
            @(negedge clk);
         end
      end // block: load_stimulus
      //
      begin: read_response
         //
         // This simulation should produce 10 packets of 10 samples containing a complex ramp waveform.
         // It should all be a single burst and each sample should increment the clock by one.
         //

         // Wait until stimulus is loaded.
         while (!ready_to_test) @(posedge clk);

         // Create Objects
         golden_packet = new;
         response_packet = new;
         // Initialize header fields with default values
         $display("----------------\nBurst %d",1);
         golden_packet.init;
         // Overide FlowID
         golden_packet.set_flow_src(SRC0);
         golden_packet.set_flow_dst(DST0);
         // Set packet length to be header plus 5 beats of 2 complex samples
         golden_packet.set_length(beats_to_bytes(3+5));
         // Set timestamp of first packet to be 1000...
         golden_packet.set_timestamp(1000);
         // Set RX MIMO metadata to arbitrary constant
         golden_packet.set_rx_mimo_metadata(TEST_RXMIMO_METADATA);
         // Explict set packet type to INT16_COMPLEX
         golden_packet.set_packet_type(INT16_COMPLEX_EXTENDED);
         for (integer i = 0; i < 10; i++) begin
            $display("Packet %d",i);
            if (i === 9) begin
               // End of Burst Reached.
               golden_packet.set_packet_type(INT16_COMPLEX_EXTENDED_EOB);
               golden_packet.set_length(beats_to_bytes(3+2));
            end
            // Initialize ramp waveform start value to zero on first pass
            golden_packet.ramp(i===0);
            axis_response_post.pop_pkt(response_packet);
            // (Assert stops implicit void cast warning)
            `FAIL_UNLESS(golden_packet.is_same(response_packet,1'b0));
            // Increment Sequence Number
            golden_packet.inc_seq_id;
            // Increment Packet Time
            golden_packet.set_timestamp(golden_packet.get_timestamp() + 10);
         end // for (integer i = 0; i < 10; i++)

         $display("----------------\nBurst %d",2);
         // Burst 2
         // Initialize header fields with default values
         golden_packet.init;
         // Overide FlowID
         golden_packet.set_flow_src(SRC0);
         golden_packet.set_flow_dst(DST0);
         // Set packet length to be header plus 5 beats of 2 complex samples
         golden_packet.set_length(beats_to_bytes(3+5));
         // Set timestamp of first packet to be 1000...
         golden_packet.set_timestamp(1000);
         // Set RX MIMO metadata to arbitrary constant
         golden_packet.set_rx_mimo_metadata(TEST_RXMIMO_METADATA);
         // Explict set packet type to INT16_COMPLEX
         golden_packet.set_packet_type(INT16_COMPLEX_EXTENDED);
         for (integer i = 0; i < 10; i++) begin
            $display("Packet %d",i);
            if (i === 9) begin
               // End of Burst Reached.
               golden_packet.set_packet_type(INT16_COMPLEX_EXTENDED_EOB);
               golden_packet.set_length(beats_to_bytes(3+2));
            end
            // Continue ramp waveform from first burst
            golden_packet.ramp(0);
            axis_response_post.pop_pkt(response_packet);
            // (Assert stops implicit void cast warning)
            `FAIL_UNLESS(golden_packet.is_same(response_packet,1'b0));
            // Increment Sequence Number
            golden_packet.inc_seq_id;
            // Increment Packet Time
            golden_packet.set_timestamp(golden_packet.get_timestamp() + 10);
         end // for (integer i = 0; i < 10; i++)

         $display("two_bursts_two_clk_per_samp: Good Response");
	 disable watchdog_thread;
      end // block: read_response
      //
      // Watchdog kills simulation if any test case fails to decisively PASS or FAIL.
      //
      begin : watchdog_thread
	 timeout = 100000;
	 while(1) begin
	    `FAIL_IF(timeout==0);
	    timeout = timeout - 1;
	    @(negedge clk);
	 end
      end
   join
   `SVTEST_END

   //-------------------------------------------------------------------------------
   // --MIXED FULL PACKETS (EXTENDED FIRST)--
   // Stream one burst containing three full-size packets with mixed formats.
   // No input throttling.
   //
   // Configured as follows:
   // start_time = 1000
   // packet_size = 10 samples
   // flow_id = {SRC0,DST0}
   // time_per_pkt = 10
   // burst_size = 30 (3 full packets)
   //
   // Packet 0 = extended, 10 samples
   // Packet 1 = legacy,   10 samples
   // Packet 2 = extended EOB, 10 samples
   //-------------------------------------------------------------------------------
   `SVTEST(mixed_full_packets_extended_eob)
      logic [31:0] sample [0:29];
      logic [63:0] expected [0:22], observed [0:22];
      logic expected_tlast [0:22], observed_tlast [0:22];

      `INFO("One burst of 3 full mixed packets: extended, legacy, extended EOB");

      for (int i = 0; i < 30; i++) begin
         sample[i] = 32'hABCD_0000 + i;
      end

      // Extended: 10 samples, 64 bytes (indices #0-7)
      expected[0] = {INT16_COMPLEX_EXTENDED, 8'h00, 16'd64,
                     {SRC0,DST0}};
      expected[1] = 64'd1000;
      expected[2] = 64'h1111_2222_3333_4444;

      for (int i = 0; i < 10; i += 2) begin
         expected[3+(i/2)] = {sample[i],sample[i+1]};
      end

      // Legacy: 10 samples, 56 bytes (indices #8-14)
      expected[8] = {INT16_COMPLEX, 8'h01, 16'd56,
                     {SRC0,DST0}};
      expected[9] = 64'd1010;

      for (int i = 10; i < 20; i += 2) begin
         expected[10+((i-10)/2)] = {sample[i],sample[i+1]};
      end

      // Extended EOB: 10 samples, 64 bytes (indices #15-22)
      expected[15] = {INT16_COMPLEX_EXTENDED_EOB, 8'h02, 16'd64,
                     {SRC0,DST0}};
      expected[16] = 64'd1020;
      expected[17] = 64'hAAAA_BBBB_CCCC_DDDD;

      for (int i = 20; i < 30; i += 2) begin
         expected[18+((i-20)/2)] = {sample[i],sample[i+1]};
      end

      for (int i = 0; i < 23; i++) begin
         expected_tlast[i] = 1'b0;
      end

      expected_tlast[7]  = 1'b1;
      expected_tlast[14] = 1'b1;
      expected_tlast[22] = 1'b1;

      // Setup this test:
      enable <= 0;
      start_time <= 1000;
      packet_size <= 10;
      flow_id <= {SRC0,DST0};
      time_per_pkt <= 10;
      burst_size <= 30;
      abort <= 0;
      // Response threads can't run until stimulus loaded.
      ready_to_test <= 0;
      // Close valve after stimulus buffer
      enable_stimulus <= 0;

      has_metadata <= 1;
      rx_mimo_metadata <= 64'h1111_2222_3333_4444;

      fork
         begin : load_stimulus
            for (int i = 0; i < 30; i++) begin
               axis_stimulus_pre.write_beat(sample[i], 1'b0);
            end

            //
            // Stimulus fully loaded, initialize system for test and release stimulus
            // by opening valve.
            //
            @(negedge clk);
            // Enable configured sub-system operation
            enable <= 1;
            @(negedge clk);
            // 100% duty cycle on AXIS input bus.
            enable_stimulus <= 1;
            // Let response threads run
            ready_to_test <= 1;
            //
         end // block: load_stimulus

         begin : drive_packet_metadata
            // Packet 0 complete
            wait_ingress_samples(10);
            @(negedge clk);
            has_metadata <= 0;
            rx_mimo_metadata <= '0;

            // Packet 1 complete
            wait_ingress_samples(10);
            @(negedge clk);
            has_metadata <= 1;
            rx_mimo_metadata <= 64'hAAAA_BBBB_CCCC_DDDD;

            // Packet 2 complete
            wait_ingress_samples(10);
         end

         begin : read_response
            // Wait until stimulus is loaded.
            while (!ready_to_test) @(posedge clk);

            for (int i = 0; i < 23; i++) begin
               axis_response_post.axis.read_beat(
                  observed[i], observed_tlast[i]);

               `FAIL_UNLESS_EQUAL(observed[i], expected[i]);
               `FAIL_UNLESS_EQUAL(observed_tlast[i], expected_tlast[i]);
            end

            disable watchdog_thread;
         end

         // Watchdog kills simulation if any test case fails to decisively PASS or FAIL.
         begin : watchdog_thread
            timeout = 100000;
            while (1) begin
               `FAIL_IF(timeout == 0);
               timeout--;
               @(negedge clk);
            end
         end
      join
   `SVTEST_END

   //-------------------------------------------------------------------------------
   // --MIXED FULL PACKETS (LEGACY FIRST)--
   // Stream one burst containing three full-size packets with mixed formats.
   // No input throttling.
   //
   // Configured as follows:
   // start_time = 1000
   // packet_size = 10 samples
   // flow_id = {SRC0,DST0}
   // time_per_pkt = 10
   // burst_size = 30 (3 full packets)
   //
   // Packet 0 = legacy, 10 samples
   // Packet 1 = extended, 10 samples
   // Packet 2 = legacy EOB, 10 samples
   //-------------------------------------------------------------------------------
   `SVTEST(mixed_full_packets_legacy_eob)
      logic [31:0] sample [0:29];
      logic [63:0] expected [0:21], observed [0:21];
      logic expected_tlast [0:21], observed_tlast [0:21];

      `INFO("One burst of 3 full mixed packets: legacy, extended, legacy EOB");

      for (int i = 0; i < 30; i++) begin
         sample[i] = 32'hABCD_0000 + i;
      end

      // Legacy: 10 samples, 56 bytes (indices #0-6)
      expected[0] = {INT16_COMPLEX, 8'h00, 16'd56, {SRC0,DST0}};
      expected[1] = 64'd1000;
      for (int i = 0; i < 10; i += 2) begin
         expected[2+(i/2)] = {sample[i],sample[i+1]};
      end

      // Extended: 10 samples, 64 bytes (indices #7-14)
      expected[7] = {INT16_COMPLEX_EXTENDED, 8'h01, 16'd64,
                     {SRC0,DST0}};
      expected[8] = 64'd1010;
      expected[9] = 64'h1111_2222_3333_4444;
      for (int i = 10; i < 20; i += 2) begin
         expected[10+((i-10)/2)] = {sample[i],sample[i+1]};
      end

      // Legacy EOB: 10 samples, 56 bytes (indices #15-21)
      expected[15] = {INT16_COMPLEX_EOB, 8'h02, 16'd56,
                     {SRC0,DST0}};
      expected[16] = 64'd1020;
      for (int i = 20; i < 30; i += 2) begin
         expected[17+((i-20)/2)] = {sample[i],sample[i+1]};
      end

      for (int i = 0; i < 22; i++) begin
         expected_tlast[i] = 1'b0;
      end
      expected_tlast[6]  = 1'b1;
      expected_tlast[14] = 1'b1;
      expected_tlast[21] = 1'b1;

      // Setup this test:
      enable <= 0;
      start_time <= 1000;
      packet_size <= 10;
      flow_id <= {SRC0,DST0};
      time_per_pkt <= 10;
      burst_size <= 30;
      abort <= 0;
      // Response threads can't run until stimulus loaded.
      ready_to_test <= 0;
      // Close valve after stimulus buffer
      enable_stimulus <= 0;

      has_metadata <= 0;
      rx_mimo_metadata <= '0;

      fork
         begin : load_stimulus
            for (int i = 0; i < 30; i++) begin
               axis_stimulus_pre.write_beat(sample[i], 1'b0);
            end

            //
            // Stimulus fully loaded, initialize system for test and release stimulus
            // by opening valve.
            //
            @(negedge clk);
            // Enable configured sub-system operation
            enable <= 1;
            @(negedge clk);
            // 100% duty cycle on AXIS input bus.
            enable_stimulus <= 1;
            // Let response threads run
            ready_to_test <= 1;
            //
         end // block: load_stimulus

         begin : drive_packet_metadata
            // Packet 0 complete
            wait_ingress_samples(10);
            @(negedge clk);
            has_metadata <= 1;
            rx_mimo_metadata <= 64'h1111_2222_3333_4444;

            // Packet 1 complete
            wait_ingress_samples(10);
            @(negedge clk);
            has_metadata <= 0;
            rx_mimo_metadata <= '0;

            // Packet 2 complete
            wait_ingress_samples(10);
         end

         begin : read_response
            // Wait until stimulus is loaded.
            while (!ready_to_test) @(posedge clk);

            for (int i = 0; i < 22; i++) begin
               axis_response_post.axis.read_beat(
                  observed[i], observed_tlast[i]);

               `FAIL_UNLESS_EQUAL(observed[i], expected[i]);
               `FAIL_UNLESS_EQUAL(observed_tlast[i], expected_tlast[i]);
            end

            disable watchdog_thread;
         end

         // Watchdog kills simulation if any test case fails to decisively PASS or FAIL.
         begin : watchdog_thread
            timeout = 100000;
            while (1) begin
               `FAIL_IF(timeout == 0);
               timeout--;
               @(negedge clk);
            end
         end
      join
   `SVTEST_END

   //-------------------------------------------------------------------------------
   // --MIXED (EXTENDED FIRST)--
   // Stream one burst containing three packets with mixed formats (legacy and extended).
   // Last packet is smaller than max packet size
   // Run input stimulus at 50% duty cycle for 1000 clocks to start.
   //
   // Configured as follows:
   // start_time = 1000
   // packet_size = 10 samples
   // flow_id = {SRC0,DST0}
   // time_per_pkt = 10 (Sample_rate=clk_rate)
   // burst_size = 26 (3 packets)
   // rx_mimo_metadata = changes per extended packet
   // has_metadata = goes high, toggles at packet boundaries
   //
   // Packet 0 = extended, 10 samples
   // Packet 1 = legacy, 10 samples
   // Packet 2 = extended, 6 samples
   //-------------------------------------------------------------------------------
   `SVTEST(mixed_partial_extended_eob)
      logic [31:0] sample [0:25];
      logic [63:0] expected [0:20], observed [0:20];
      logic expected_tlast [0:20], observed_tlast [0:20];
      `INFO("One partial burst of 3 mixed packets: extended, legacy, extended EOB");

      for (int i = 0; i < 26; i++) begin
         sample[i] = 32'hABCD_0000 + i;
      end

      // Extended: 10 samples, 64 bytes (indices #0-7)
      expected[0] = {INT16_COMPLEX_EXTENDED, 8'h00, 16'd64, {SRC0,DST0}};
      expected[1] = 64'd1000;
      expected[2] = 64'h1111_2222_3333_4444;
      for (int i = 0; i < 10; i += 2) begin
         expected[3+(i/2)] = {sample[i],sample[i+1]};
      end

      // Legacy: 10 samples, 56 bytes (indices #8-14)
      expected[8] = {INT16_COMPLEX, 8'h01, 16'd56, {SRC0,DST0}};
      expected[9] = 64'd1010;
      for (int i = 10; i < 20; i += 2) begin
         expected[10+((i-10)/2)] = {sample[i],sample[i+1]};
      end
      
      // Partial extended EOB: 6 samples, 48 bytes (indices #15-20)
      expected[15] = {INT16_COMPLEX_EXTENDED_EOB, 8'h02, 16'd48,
                     {SRC0,DST0}};
      expected[16] = 64'd1020;
      expected[17] = 64'hAAAA_BBBB_CCCC_DDDD;
      for (int i = 20; i < 26; i += 2) begin
         expected[18+((i-20)/2)] = {sample[i],sample[i+1]};
      end

      for (int i = 0; i < 21; i++) begin
         expected_tlast[i] = 1'b0;
      end
      expected_tlast[7]  = 1'b1;
      expected_tlast[14] = 1'b1;
      expected_tlast[20] = 1'b1;

      // Setup this test:
      enable <= 0;
      start_time <= 1000;
      packet_size <= 10;
      flow_id <= {SRC0,DST0};
      time_per_pkt <= 10;
      burst_size <= 26;
      abort <= 0;
      // Response threads can't run until stimulus loaded.
      ready_to_test <= 0;
      // Close valve after stimulus buffer
      enable_stimulus <= 0;
      has_metadata <= 1;
      rx_mimo_metadata <= 64'h1111_2222_3333_4444;

      fork
         begin : load_stimulus
            for (int i = 0; i < 26; i++) begin
               axis_stimulus_pre.write_beat(sample[i], 1'b0);
            end

            //
            // Stimulus fully loaded, initialize system for test and release stimulus
            // by opening valve.
            //
            @(negedge clk);
            // Enable configured sub-system operation
            enable <= 1;
            @(negedge clk);
            // Let response threads run
            ready_to_test <= 1;
            //
            // 1000 clock cycles of 50% duty cycle on AXIS input bus
            // then go 100% duty cycle
            //
            repeat(500) begin
               enable_stimulus <= 1'b0;
               @(negedge clk);
               enable_stimulus <= 1'b1;
               @(negedge clk);
            end
         end // block: load_stimulus

         begin : drive_packet_metadata
            wait_ingress_samples(10);
            @(negedge clk);
            has_metadata <= 0;
            rx_mimo_metadata <= '0;

            wait_ingress_samples(10);
            @(negedge clk);
            has_metadata <= 1;
            rx_mimo_metadata <= 64'hAAAA_BBBB_CCCC_DDDD;

            wait_ingress_samples(6);
         end

         begin : read_response
            // Wait until stimulus is loaded.
            while (!ready_to_test) @(posedge clk);

            for (int i = 0; i < 21; i++) begin
               axis_response_post.axis.read_beat(
                  observed[i], observed_tlast[i]);

               `FAIL_UNLESS_EQUAL(observed[i], expected[i]);
               `FAIL_UNLESS_EQUAL(observed_tlast[i], expected_tlast[i]);
            end

            disable watchdog_thread;
         end

         // Watchdog kills simulation if any test case fails to decisively PASS or FAIL.
         begin : watchdog_thread
            timeout = 100000;
            while (1) begin
               `FAIL_IF(timeout == 0);
               timeout--;
               @(negedge clk);
            end
         end
      join
   `SVTEST_END

   //-------------------------------------------------------------------------------
   // --MIXED (LEGACY FIRST)--
   // Stream one burst containing three packets with mixed formats (legacy and extended).
   // Last packet is smaller than max packet size
   // Run input stimulus at 50% duty cycle for 1000 clocks to start.
   //
   // Configured as follows:
   // start_time = 1000
   // packet_size = 10 samples
   // flow_id = {SRC0,DST0}
   // time_per_pkt = 10 (Sample_rate=clk_rate)
   // burst_size = 26 (3 packets)
   // rx_mimo_metadata = used for extended packet
   // has_metadata = toggles at packet boundaries
   //
   // Packet 0 = legacy, 10 samples
   // Packet 1 = extended, 10 samples
   // Packet 2 = legacy EOB, 6 samples
   //-------------------------------------------------------------------------------
   `SVTEST(mixed_partial_legacy_eob)
      logic [31:0] sample [0:25];
      logic [63:0] expected [0:19], observed [0:19];
      logic expected_tlast [0:19], observed_tlast [0:19];
      `INFO("One partial burst of 3 mixed packets: legacy, extended, legacy EOB");

      for (int i = 0; i < 26; i++) begin
         sample[i] = 32'hABCD_0000 + i;
      end

      // Legacy: 10 samples, 56 bytes (indices #0-6)
      expected[0] = {INT16_COMPLEX, 8'h00, 16'd56, {SRC0,DST0}};
      expected[1] = 64'd1000;
      for (int i = 0; i < 10; i += 2) begin
         expected[2+(i/2)] = {sample[i],sample[i+1]};
      end

      // Extended: 10 samples, 64 bytes (indices #7-14)
      expected[7] = {INT16_COMPLEX_EXTENDED, 8'h01, 16'd64, {SRC0,DST0}};
      expected[8] = 64'd1010;
      expected[9] = 64'h1111_2222_3333_4444;
      for (int i = 10; i < 20; i += 2) begin
         expected[10+((i-10)/2)] = {sample[i],sample[i+1]};
      end
      
      // Partial legacy EOB: 6 samples, 40 bytes (indices #15-19)
      expected[15] = {INT16_COMPLEX_EOB, 8'h02, 16'd40, {SRC0,DST0}};
      expected[16] = 64'd1020;
      for (int i = 20; i < 26; i += 2) begin
         expected[17+((i-20)/2)] = {sample[i],sample[i+1]};
      end

      for (int i = 0; i < 20; i++) begin
         expected_tlast[i] = 1'b0;
      end
      expected_tlast[6]  = 1'b1;
      expected_tlast[14] = 1'b1;
      expected_tlast[19] = 1'b1;

      // Setup this test:
      enable <= 0;
      start_time <= 1000;
      packet_size <= 10;
      flow_id <= {SRC0,DST0};
      time_per_pkt <= 10;
      burst_size <= 26;
      abort <= 0;
      // Response threads can't run until stimulus loaded.
      ready_to_test <= 0;
      // Close valve after stimulus buffer
      enable_stimulus <= 0;
      has_metadata <= 0;
      rx_mimo_metadata <= '0;

      fork
         begin : load_stimulus
            for (int i = 0; i < 26; i++) begin
               axis_stimulus_pre.write_beat(sample[i], 1'b0);
            end

            //
            // Stimulus fully loaded, initialize system for test and release stimulus
            // by opening valve.
            //
            @(negedge clk);
            // Enable configured sub-system operation
            enable <= 1;
            @(negedge clk);
            // Let response threads run
            ready_to_test <= 1;
            //
            // 1000 clock cycles of 50% duty cycle on AXIS input bus
            // then go 100% duty cycle
            //
            repeat(500) begin
               enable_stimulus <= 1'b0;
               @(negedge clk);
               enable_stimulus <= 1'b1;
               @(negedge clk);
            end
         end // block: load_stimulus

         begin : drive_packet_metadata
            wait_ingress_samples(10);
            @(negedge clk);
            has_metadata <= 1;
            rx_mimo_metadata <= 64'h1111_2222_3333_4444;

            wait_ingress_samples(10);
            @(negedge clk);
            has_metadata <= 0;
            rx_mimo_metadata <= '0;

            wait_ingress_samples(6);
         end

         begin : read_response
            // Wait until stimulus is loaded.
            while (!ready_to_test) @(posedge clk);

            for (int i = 0; i < 20; i++) begin
               axis_response_post.axis.read_beat(
                  observed[i], observed_tlast[i]);

               `FAIL_UNLESS_EQUAL(observed[i], expected[i]);
               `FAIL_UNLESS_EQUAL(observed_tlast[i], expected_tlast[i]);
            end

            disable watchdog_thread;
         end

         // Watchdog kills simulation if any test case fails to decisively PASS or FAIL.
         begin : watchdog_thread
            timeout = 100000;
            while (1) begin
               `FAIL_IF(timeout == 0);
               timeout--;
               @(negedge clk);
            end
         end
      join
   `SVTEST_END

      //-------------------------------------------------------------------------------
      // --MIXED TWO BURSTS (EXTENDED FIRST)--
      // Stream two bursts with mixed packet formats.
      // Last packet of each burst is smaller than max packet size.
      // Run input stimulus at 50% duty cycle for 1000 clocks to start.
      //
      // Configured as follows:
      // start_time = 1000
      // packet_size = 10 samples
      // flow_id = {SRC0,DST0}
      // time_per_pkt = 10
      // burst_size = 24 samples per burst
      //
      // Burst 1:
      // Packet 0 = extended,     10 samples
      // Packet 1 = legacy,       10 samples
      // Packet 2 = extended EOB,  4 samples
      //
      // Burst 2:
      // Packet 0 = legacy,       10 samples
      // Packet 1 = extended,     10 samples
      // Packet 2 = legacy EOB,    4 samples
      //-------------------------------------------------------------------------------
      `SVTEST(mixed_two_bursts_extended_first)
         logic [31:0] sample [0:47];
         logic [63:0] expected [0:38], observed [0:38];
         logic expected_tlast [0:38], observed_tlast [0:38];

         `INFO("Two bursts of 3 mixed packets, extended first");

         for (int i = 0; i < 48; i++) begin
            sample[i] = 32'hABCD_0000 + i;
         end

         //---------------------------------------------------------------------------
         // Burst 1
         //---------------------------------------------------------------------------

         // Extended: 10 samples, 64 bytes
         expected[0] = {INT16_COMPLEX_EXTENDED, 8'h00, 16'd64,
                        {SRC0,DST0}};
         expected[1] = 64'd1000;
         expected[2] = 64'h1111_2222_3333_4444;
         for (int i = 0; i < 10; i += 2) begin
            expected[3+(i/2)] = {sample[i],sample[i+1]};
         end

         // Legacy: 10 samples, 56 bytes
         expected[8] = {INT16_COMPLEX, 8'h01, 16'd56,
                        {SRC0,DST0}};
         expected[9] = 64'd1010;
         for (int i = 10; i < 20; i += 2) begin
            expected[10+((i-10)/2)] = {sample[i],sample[i+1]};
         end

         // Extended EOB: 4 samples, 40 bytes
         expected[15] = {INT16_COMPLEX_EXTENDED_EOB, 8'h02, 16'd40,
                        {SRC0,DST0}};
         expected[16] = 64'd1020;
         expected[17] = 64'hAAAA_BBBB_CCCC_DDDD;
         for (int i = 20; i < 24; i += 2) begin
            expected[18+((i-20)/2)] = {sample[i],sample[i+1]};
         end

         //---------------------------------------------------------------------------
         // Burst 2
         // Sequence number and timestamp restart for new burst.
         //---------------------------------------------------------------------------

         // Legacy: 10 samples, 56 bytes
         expected[20] = {INT16_COMPLEX, 8'h00, 16'd56,
                        {SRC0,DST0}};
         expected[21] = 64'd1000;
         for (int i = 24; i < 34; i += 2) begin
            expected[22+((i-24)/2)] = {sample[i],sample[i+1]};
         end

         // Extended: 10 samples, 64 bytes
         expected[27] = {INT16_COMPLEX_EXTENDED, 8'h01, 16'd64,
                        {SRC0,DST0}};
         expected[28] = 64'd1010;
         expected[29] = 64'h1111_2222_3333_4444;
         for (int i = 34; i < 44; i += 2) begin
            expected[30+((i-34)/2)] = {sample[i],sample[i+1]};
         end

         // Legacy EOB: 4 samples, 32 bytes
         expected[35] = {INT16_COMPLEX_EOB, 8'h02, 16'd32,
                        {SRC0,DST0}};
         expected[36] = 64'd1020;
         for (int i = 44; i < 48; i += 2) begin
            expected[37+((i-44)/2)] = {sample[i],sample[i+1]};
         end

         for (int i = 0; i < 39; i++) begin
            expected_tlast[i] = 1'b0;
         end

         expected_tlast[7]  = 1'b1;
         expected_tlast[14] = 1'b1;
         expected_tlast[19] = 1'b1;
         expected_tlast[26] = 1'b1;
         expected_tlast[34] = 1'b1;
         expected_tlast[38] = 1'b1;

         // Setup this test:
         enable <= 0;
         start_time <= 1000;
         packet_size <= 10;
         flow_id <= {SRC0,DST0};
         time_per_pkt <= 10;
         burst_size <= 24;
         abort <= 0;
         // Response threads can't run until stimulus loaded.
         ready_to_test <= 0;
         // Close valve after stimulus buffer
         enable_stimulus <= 0;

         has_metadata <= 1;
         rx_mimo_metadata <= 64'h1111_2222_3333_4444;

         fork
            begin : load_stimulus
               for (int i = 0; i < 48; i++) begin
                  axis_stimulus_pre.write_beat(sample[i], 1'b0);
               end

               //
               // Stimulus fully loaded, initialize system for test and release stimulus
               // by opening valve.
               //
               @(negedge clk);
               // Enable configured sub-system operation
               enable <= 1;
               @(negedge clk);
               // Let response threads run
               ready_to_test <= 1;
               //
               // 1000 clock cycles of 50% duty cycle on AXIS input bus
               // then go 100% duty cycle
               //
               repeat(500) begin
                  enable_stimulus <= 1'b0;
                  @(negedge clk);
                  enable_stimulus <= 1'b1;
                  @(negedge clk);
               end
            end // block: load_stimulus

            begin : drive_packet_metadata
               // Burst 1: extended -> legacy -> extended EOB
               wait_ingress_samples(10);
               @(negedge clk);
               has_metadata <= 0;
               rx_mimo_metadata <= '0;

               wait_ingress_samples(10);
               @(negedge clk);
               has_metadata <= 1;
               rx_mimo_metadata <= 64'hAAAA_BBBB_CCCC_DDDD;

               wait_ingress_samples(4);

               // Burst 2: legacy -> extended -> legacy EOB
               @(negedge clk);
               has_metadata <= 0;
               rx_mimo_metadata <= '0;

               wait_ingress_samples(10);
               @(negedge clk);
               has_metadata <= 1;
               rx_mimo_metadata <= 64'h1111_2222_3333_4444;

               wait_ingress_samples(10);
               @(negedge clk);
               has_metadata <= 0;
               rx_mimo_metadata <= '0;

               wait_ingress_samples(4);
            end

            begin : read_response
               // Wait until stimulus is loaded.
               while (!ready_to_test) @(posedge clk);

               for (int i = 0; i < 39; i++) begin
                  axis_response_post.axis.read_beat(
                     observed[i], observed_tlast[i]);

                  `FAIL_UNLESS_EQUAL(observed[i], expected[i]);
                  `FAIL_UNLESS_EQUAL(observed_tlast[i], expected_tlast[i]);
               end

               disable watchdog_thread;
            end

            // Watchdog kills simulation if any test case fails to decisively PASS or FAIL.
            begin : watchdog_thread
               timeout = 100000;
               while (1) begin
                  `FAIL_IF(timeout == 0);
                  timeout--;
                  @(negedge clk);
               end
            end
         join
      `SVTEST_END

      //-------------------------------------------------------------------------------
      // -- ONE SAMPLE LEGACY PACKET --
      // Exercises packet_size=1 / burst_size=1 corner case.
      //-------------------------------------------------------------------------------
      `SVTEST(single_sample_legacy)
         logic [31:0] sample;
         logic [63:0] expected [0:2], observed [0:2];
         logic expected_tlast [0:2], observed_tlast [0:2];

         `INFO("One-sample legacy EOB packet");

         sample = 32'hDEAD_0001;

         // 16 byte legacy header + 4 byte sample = 20 bytes
         expected[0] = {INT16_COMPLEX_EOB, 8'h00, 16'd20, {SRC0,DST0}};
         expected[1] = 64'd1000;
         // Odd final sample is duplicated into the 64-bit sample beat
         expected[2] = {sample, sample};

         expected_tlast[0] = 1'b0;
         expected_tlast[1] = 1'b0;
         expected_tlast[2] = 1'b1;

         enable <= 0;
         start_time <= 1000;
         packet_size <= 1;
         flow_id <= {SRC0,DST0};
         time_per_pkt <= 10;
         burst_size <= 1;
         has_metadata <= 0;
         rx_mimo_metadata <= '0;
         abort <= 0;
         ready_to_test <= 0;
         enable_stimulus <= 0;

         fork
            begin : load_stimulus
               axis_stimulus_pre.write_beat(sample, 1'b0);

               @(negedge clk);
               enable <= 1;
               @(negedge clk);
               enable_stimulus <= 1;
               ready_to_test <= 1;
            end

            begin : read_response
               while (!ready_to_test) @(posedge clk);

               for (int i = 0; i < 3; i++) begin
                  axis_response_post.axis.read_beat(
                     observed[i], observed_tlast[i]);

                  `FAIL_UNLESS_EQUAL(observed[i], expected[i]);
                  `FAIL_UNLESS_EQUAL(observed_tlast[i], expected_tlast[i]);
               end

               disable watchdog_thread;
            end

            begin : watchdog_thread
               timeout = 10000;
               while (1) begin
                  `FAIL_IF(timeout == 0);
                  timeout--;
                  @(negedge clk);
               end
            end
         join
      `SVTEST_END


      //-------------------------------------------------------------------------------
      // -- ONE SAMPLE EXTENDED PACKET --
      // Exercises snapshot + same-cycle FIFO write corner case.
      //-------------------------------------------------------------------------------
      `SVTEST(single_sample_extended)
         logic [31:0] sample;
         logic [63:0] expected [0:3], observed [0:3];
         logic expected_tlast [0:3], observed_tlast [0:3];

         `INFO("One-sample extended EOB packet");

         sample = 32'hBEEF_0001;

         // 24 byte extended header + 4 byte sample = 28 bytes
         expected[0] = {INT16_COMPLEX_EXTENDED_EOB, 8'h00, 16'd28,
                        {SRC0,DST0}};
         expected[1] = 64'd1000;
         expected[2] = TEST_RXMIMO_METADATA;
         expected[3] = {sample, sample};

         expected_tlast[0] = 1'b0;
         expected_tlast[1] = 1'b0;
         expected_tlast[2] = 1'b0;
         expected_tlast[3] = 1'b1;

         enable <= 0;
         start_time <= 1000;
         packet_size <= 1;
         flow_id <= {SRC0,DST0};
         time_per_pkt <= 10;
         burst_size <= 1;
         has_metadata <= 1;
         rx_mimo_metadata <= TEST_RXMIMO_METADATA;
         abort <= 0;
         ready_to_test <= 0;
         enable_stimulus <= 0;

         fork
            begin : load_stimulus
               axis_stimulus_pre.write_beat(sample, 1'b0);

               @(negedge clk);
               enable <= 1;
               @(negedge clk);
               enable_stimulus <= 1;
               ready_to_test <= 1;
            end

            begin : read_response
               while (!ready_to_test) @(posedge clk);

               for (int i = 0; i < 4; i++) begin
                  axis_response_post.axis.read_beat(
                     observed[i], observed_tlast[i]);

                  `FAIL_UNLESS_EQUAL(observed[i], expected[i]);
                  `FAIL_UNLESS_EQUAL(observed_tlast[i], expected_tlast[i]);
               end

               disable watchdog_thread;
            end

            begin : watchdog_thread
               timeout = 10000;
               while (1) begin
                  `FAIL_IF(timeout == 0);
                  timeout--;
                  @(negedge clk);
               end
            end
         join
      `SVTEST_END


     `SVUNIT_TESTS_END

       //-------------------------------------------------------------------------------
       // Helper tasks to improve code reuse for this specific test bench.
       //-------------------------------------------------------------------------------

       // Task: idle_all()
       // Cause all AXIS buses to go idle.
       task idle_all();
          axis_stimulus_pre.idle_master();
          axis_response_post.axis.idle_slave();
       endtask // idle_all

      // Task: wait_ingress_samples()
      // Wait for a specified number of samples to be accepted by the DUT.
      task automatic wait_ingress_samples(input int unsigned count);
         int unsigned accepted = 0;

         while (accepted < count) begin
            @(posedge clk);
            if (axis_stimulus_gated.tvalid && axis_stimulus_gated.tready)
               accepted++;
         end
      endtask

endmodule
