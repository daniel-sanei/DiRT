//-----------------------------------------------------------------------------
// File:    drat_protocol_unit_test.sv
// 
// Author: Daniel Sanei, FPGA Engineer
//
// Description:
// Unit tests for extended DRaT protocol definitions and helpers.
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

`include "svunit_defines.svh"
`include "drat_protocol.sv"

module drat_protocol_unit_test;
    timeunit 1ns;
    timeprecision 1ps;
    import drat_protocol::*;
    import svunit_pkg::svunit_testcase;

    string name = "drat_protocol_ut";
    svunit_testcase svunit_ut;


    //=========================================================================
    // Constants
    //=========================================================================
    localparam pkt_type_t PACKET_TYPE = INT16_COMPLEX_EXTENDED; // 8'h40
    localparam logic [7:0] TEST_SEQ_ID = 8'h1A;
    localparam logic [15:0] TEST_LENGTH = 16'hB2C3;
    localparam logic [31:0] TEST_FLOW_ID = 32'h4D5E_6789;
    localparam logic [63:0] TEST_TIMESTAMP_BEAT = 64'hABCD_1234_EF56_0078;
    localparam logic [63:0] TEST_MIMO_BEAT = 64'hA1B2_C3D4_E5F6_0101;

    localparam logic [63:0] TEST_HEADER_BEAT = 64'h401A_B2C3_4D5E_6789;
    localparam logic [191:0] TEST_FULL_HEADER = {
        TEST_HEADER_BEAT, TEST_TIMESTAMP_BEAT, TEST_MIMO_BEAT};

    localparam logic [63:0] TEST_PAYLOAD_0 = 64'h8888_6666_4444_2222;
    localparam logic [63:0] TEST_PAYLOAD_1 = 64'hFFFF_DDDD_BBBB_0000;

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
    // Packet stream interface
    //=========================================================================
    pkt_stream_extended_t extended_stream(.clk(clk));


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

        // extended_stream.axis.idle_master();
        // extended_stream.axis.idle_slave();
        extended_stream.axis.tdata = '0;
        extended_stream.axis.tvalid = 1'b0;
        extended_stream.axis.tlast = 1'b0;
        extended_stream.axis.tready = 1'b0;
        @(posedge clk);

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
    // DRaT Definitions & Helper Functions
    //=========================================================================
    // Definitions
    //-------------------------------------------------------------------------
    `SVTEST(extended_packet_type_encodings)
        `FAIL_UNLESS_EQUAL(INT16_COMPLEX_EXTENDED, 8'h40);
        `FAIL_UNLESS_EQUAL(INT16_COMPLEX_EXTENDED_EOB, 8'h50);
        `FAIL_UNLESS_EQUAL(INT16_COMPLEX_EXTENDED_ASYNC, 8'h60);
        `FAIL_UNLESS_EQUAL(INT16_COMPLEX_EXTENDED_ASYNC_EOB, 8'h70);

    `SVTEST_END
    
    `SVTEST(header_struct_widths)
        `FAIL_UNLESS_EQUAL($bits(pkt_header_t), 128);
        `FAIL_UNLESS_EQUAL($bits(pkt_header_extended_t), 192);

    `SVTEST_END

    //-------------------------------------------------------------------------
    // Helper functions
    //-------------------------------------------------------------------------
    `SVTEST(extract_header_fields)
        pkt_header_extended_t test_header;
        test_header.packet_type = PACKET_TYPE;
        test_header.seq_id = TEST_SEQ_ID;
        test_header.length = TEST_LENGTH;
        test_header.flow_id = TEST_FLOW_ID;
        test_header.timestamp = TEST_TIMESTAMP_BEAT;
        test_header.rx_mimo_metadata = TEST_MIMO_BEAT;

        `FAIL_UNLESS_EQUAL(extract_header_extended(test_header), TEST_HEADER_BEAT);
        `FAIL_UNLESS_EQUAL(extract_timestamp_extended(test_header), TEST_TIMESTAMP_BEAT);
        `FAIL_UNLESS_EQUAL(extract_rx_mimo_extended(test_header), TEST_MIMO_BEAT);

    `SVTEST_END

    `SVTEST(populate_extended_headers)
        pkt_header_extended_t populated_header;
        populated_header = populate_header_extended(TEST_FULL_HEADER);

        `FAIL_UNLESS_EQUAL(populated_header.packet_type, PACKET_TYPE);
        `FAIL_UNLESS_EQUAL(populated_header.seq_id, TEST_SEQ_ID);
        `FAIL_UNLESS_EQUAL(populated_header.length, TEST_LENGTH);
        `FAIL_UNLESS_EQUAL(populated_header.flow_id, TEST_FLOW_ID);
        `FAIL_UNLESS_EQUAL(populated_header.flow_id.flow_id, TEST_FLOW_ID);
        `FAIL_UNLESS_EQUAL(populated_header.timestamp, TEST_TIMESTAMP_BEAT);
        `FAIL_UNLESS_EQUAL(populated_header.rx_mimo_metadata, TEST_MIMO_BEAT);

        `FAIL_UNLESS_EQUAL(extract_header_extended(populated_header), TEST_HEADER_BEAT);
        `FAIL_UNLESS_EQUAL(extract_timestamp_extended(populated_header), TEST_TIMESTAMP_BEAT);
        `FAIL_UNLESS_EQUAL(extract_rx_mimo_extended(populated_header), TEST_MIMO_BEAT);

    `SVTEST_END

    `SVTEST(populate_extended_headers_no_timestamp_rxmimo)
        pkt_header_extended_t populated_header;
        populated_header = populate_header_extended_no_timestamp(TEST_HEADER_BEAT);

        `FAIL_UNLESS_EQUAL(populated_header.packet_type, PACKET_TYPE);
        `FAIL_UNLESS_EQUAL(populated_header.seq_id, TEST_SEQ_ID);
        `FAIL_UNLESS_EQUAL(populated_header.length, TEST_LENGTH);
        `FAIL_UNLESS_EQUAL(populated_header.flow_id, TEST_FLOW_ID);
        `FAIL_UNLESS_EQUAL(populated_header.flow_id.flow_id, TEST_FLOW_ID);
        `FAIL_UNLESS_EQUAL(populated_header.timestamp, 64'h0000_0000_0000_0000);
        `FAIL_UNLESS_EQUAL(populated_header.rx_mimo_metadata, 64'h0000_0000_0000_0000);

        `FAIL_UNLESS_EQUAL(extract_header_extended(populated_header), TEST_HEADER_BEAT);
        `FAIL_UNLESS_EQUAL(extract_timestamp_extended(populated_header), 64'h0000_0000_0000_0000);
        `FAIL_UNLESS_EQUAL(extract_rx_mimo_extended(populated_header), 64'h0000_0000_0000_0000);

    `SVTEST_END

    `SVTEST(compare_extended_headers)
        pkt_header_extended_t header_1;
        pkt_header_extended_t header_2;
        header_1 = populate_header_extended(TEST_FULL_HEADER);
        header_2 = populate_header_extended(TEST_FULL_HEADER);
        
        `FAIL_UNLESS_EQUAL(header_extended_compare(header_1, header_2), 1'b1);

        header_2.rx_mimo_metadata = 64'h1234_5678_ABCD_EF00;
        `FAIL_UNLESS_EQUAL(header_1.packet_type, header_2.packet_type);
        `FAIL_UNLESS_EQUAL(header_1.seq_id, header_2.seq_id);
        `FAIL_UNLESS_EQUAL(header_1.length, header_2.length);
        `FAIL_UNLESS_EQUAL(header_1.flow_id, header_2.flow_id);
        `FAIL_UNLESS_EQUAL(header_1.flow_id.flow_id, header_2.flow_id.flow_id);
        `FAIL_UNLESS_EQUAL(header_1.timestamp, header_2.timestamp);
        `FAIL_UNLESS(header_extended_compare(header_1, header_2) === 1'b0);

        header_2.rx_mimo_metadata = 64'hA1B2_C3D4_E5F6_0101;
        `FAIL_UNLESS_EQUAL(header_1.packet_type, header_2.packet_type);
        `FAIL_UNLESS_EQUAL(header_1.seq_id, header_2.seq_id);
        `FAIL_UNLESS_EQUAL(header_1.length, header_2.length);
        `FAIL_UNLESS_EQUAL(header_1.flow_id, header_2.flow_id);
        `FAIL_UNLESS_EQUAL(header_1.flow_id.flow_id, header_2.flow_id.flow_id);
        `FAIL_UNLESS_EQUAL(header_1.timestamp, header_2.timestamp);
        `FAIL_UNLESS(header_extended_compare(header_1, header_2) === 1'b1);

    `SVTEST_END


    //=========================================================================
    // DRaTPacketExtended class tests
    //=========================================================================
    // Constructor initializations
    //-------------------------------------------------------------------------
    `SVTEST(drat_extended_constructor)
        DRaTPacketExtended packet = new();
        pkt_header_extended_t header = packet.get_header();

        `FAIL_UNLESS_EQUAL(header.packet_type, PACKET_TYPE);
        `FAIL_UNLESS_EQUAL(header.seq_id, 8'h00);
        `FAIL_UNLESS_EQUAL(header.length, 16'd8);
        `FAIL_UNLESS_EQUAL(header.flow_id, 32'h0000_0000);
        `FAIL_UNLESS_EQUAL(header.flow_id.flow_id, 32'h0000_0000);
        `FAIL_UNLESS_EQUAL(header.timestamp, 64'h0000_0000_0000_0000);
        `FAIL_UNLESS_EQUAL(header.rx_mimo_metadata, 64'h0000_0000_0000_0000);

    `SVTEST_END

    //-------------------------------------------------------------------------
    // Getter/setter functions
    //-------------------------------------------------------------------------
    `SVTEST(drat_extended_getter_setter)
        DRaTPacketExtended packet = new();
        logic [63:0] test_raw_header = 64'h4012_3456_7890_ABCD;
        logic [63:0] test_timestamp_beat = 64'h0000_1111_0000_1010;
        logic [63:0] test_mimo_beat = 64'h9010_8020_7030_6040;
        logic [191:0] new_full_header;

        //`FAIL_UNLESS_EQUAL(packet.get_length(), TEST_LENGTH);
        
        packet.set_packet_type(PACKET_TYPE);
        packet.set_seq_id(TEST_SEQ_ID);
        packet.set_length(TEST_LENGTH);
        packet.set_flow_id(TEST_FLOW_ID);
        packet.set_timestamp(TEST_TIMESTAMP_BEAT);
        packet.set_rx_mimo_metadata(TEST_MIMO_BEAT);

        `FAIL_UNLESS_EQUAL(packet.get_packet_type(), PACKET_TYPE);
        `FAIL_UNLESS_EQUAL(packet.get_seq_id(), TEST_SEQ_ID);
        `FAIL_UNLESS_EQUAL(packet.get_length(), TEST_LENGTH);
        `FAIL_UNLESS_EQUAL(packet.get_flow_id(), TEST_FLOW_ID);
        `FAIL_UNLESS_EQUAL(packet.get_flow_id().flow_id, TEST_FLOW_ID);
        `FAIL_UNLESS_EQUAL(packet.get_timestamp(), TEST_TIMESTAMP_BEAT);
        `FAIL_UNLESS_EQUAL(packet.get_rx_mimo_metadata(), TEST_MIMO_BEAT);
        `FAIL_UNLESS_EQUAL(packet.get_header(), TEST_FULL_HEADER);

        packet.set_raw_header(test_raw_header);
        `FAIL_UNLESS_EQUAL(packet.get_raw_header(), test_raw_header);
        `FAIL_UNLESS_EQUAL(packet.get_packet_type(), INT16_COMPLEX_EXTENDED);
        `FAIL_UNLESS_EQUAL(packet.get_seq_id(), 8'h12);
        `FAIL_UNLESS_EQUAL(packet.get_length(), 16'h3456);
        `FAIL_UNLESS_EQUAL(packet.get_flow_id(), 32'h7890_ABCD);
        `FAIL_UNLESS_EQUAL(packet.get_timestamp(), TEST_TIMESTAMP_BEAT);
        `FAIL_UNLESS_EQUAL(packet.get_rx_mimo_metadata(), TEST_MIMO_BEAT);

        new_full_header = {test_raw_header, test_timestamp_beat, test_mimo_beat};
        packet.set_header(new_full_header);
        `FAIL_UNLESS_EQUAL(packet.get_header(), new_full_header);

    `SVTEST_END

    //-------------------------------------------------------------------------
    // Payload handling
    //-------------------------------------------------------------------------
    `SVTEST(drat_extended_payload_reset)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;

        packet.reset_payload();
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 1);

        packet.reset_payload(2);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 2);

        packet.reset_payload(5);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 5);

    `SVTEST_END

    `SVTEST(drat_extended_payload_allocation)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;

        packet.set_length(16'd24);
        packet.allocate_payload();
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 0);

        packet.set_length(16'd32);
        packet.allocate_payload();
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 1);

        packet.set_length(16'd40);
        packet.allocate_payload();
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 2);

    `SVTEST_END

    `SVTEST(drat_extended_payload_manual_allocation)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;
        logic [63:0] beat0 = 64'h0000_1111_2222_3333;
        logic [63:0] beat1 = 64'h4444_5555_AAAA_BBBB;
        logic [63:0] beat2 = 64'hCCCC_DDDD_EEEE_FFFF;
        logic [63:0] observed;

        packet.set_length(16'd32);
        packet.allocate_payload();
        packet.rewind_payload();
        packet.set_beat(beat0);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 1);
        `FAIL_UNLESS_EQUAL(payload[0], beat0);

        packet.set_length(16'd40);
        packet.allocate_payload();
        packet.rewind_payload();
        packet.set_beat(beat0);
        packet.set_beat(beat1);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 2);
        `FAIL_UNLESS_EQUAL(payload[0], beat0);
        `FAIL_UNLESS_EQUAL(payload[1], beat1);

        packet.set_length(16'd48);
        packet.allocate_payload();
        packet.rewind_payload();
        packet.set_beat(beat0);
        packet.set_beat(beat1);
        packet.set_beat(beat2);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 3);
        `FAIL_UNLESS_EQUAL(payload[0], beat0);
        `FAIL_UNLESS_EQUAL(payload[1], beat1);
        `FAIL_UNLESS_EQUAL(payload[2], beat2);

        packet.rewind_payload();
        observed = packet.get_beat();
        `FAIL_UNLESS_EQUAL(observed, beat0);
        observed = packet.get_beat();
        `FAIL_UNLESS_EQUAL(observed, beat1);
        observed = packet.get_beat();
        `FAIL_UNLESS_EQUAL(observed, beat2);

    `SVTEST_END

    `SVTEST(drat_extended_payload_auto_allocation)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;
        logic [63:0] beat0 = 64'hAAAA_BBBB_CCCC_DDDD;
        logic [63:0] beat1 = 64'hEEEE_FFFF_1111_2222;
        logic [63:0] beat2 = 64'h3333_4444_5555_6666;
        logic [63:0] observed;

        packet.set_length(16'd24);
        `FAIL_UNLESS_EQUAL(packet.get_length(), 16'd24);
        packet.add_beat(beat0);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(packet.get_length(), 16'd32);
        `FAIL_UNLESS_EQUAL(payload.size(), 1);
        `FAIL_UNLESS_EQUAL(payload[0], beat0);
        packet.add_beat(beat1);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(packet.get_length(), 16'd40);
        `FAIL_UNLESS_EQUAL(payload.size(), 2);
        `FAIL_UNLESS_EQUAL(payload[0], beat0);
        `FAIL_UNLESS_EQUAL(payload[1], beat1);
        packet.add_beat(beat2);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(packet.get_length(), 16'd48);
        `FAIL_UNLESS_EQUAL(payload.size(), 3);
        `FAIL_UNLESS_EQUAL(payload[0], beat0);
        `FAIL_UNLESS_EQUAL(payload[1], beat1);
        `FAIL_UNLESS_EQUAL(payload[2], beat2);

        packet.rewind_payload();
        observed = packet.get_beat();
        `FAIL_UNLESS_EQUAL(observed, beat0);
        observed = packet.get_beat();
        `FAIL_UNLESS_EQUAL(observed, beat1);
        observed = packet.get_beat();
        `FAIL_UNLESS_EQUAL(observed, beat2);

    `SVTEST_END

    //-------------------------------------------------------------------------
    // Helper functions
    //-------------------------------------------------------------------------
    `SVTEST(drat_extended_payload_random)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;

        packet.set_length(16'd24);
        packet.random();
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 0);

        packet.set_length(16'd32);
        packet.random();
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 1);

        packet.set_length(16'd40);
        packet.random();
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 2);

    `SVTEST_END

    `SVTEST(drat_extended_payload_ramp)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;

        packet.set_length(16'd40);
        packet.ramp();
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 2);
        `FAIL_UNLESS_EQUAL(payload[0].beat, 64'h0000_0001_0002_0003);
        `FAIL_UNLESS_EQUAL(payload[1].beat, 64'h0004_0005_0006_0007);

        packet.ramp();
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 2);
        `FAIL_UNLESS_EQUAL(payload[0].beat, 64'h0000_0001_0002_0003);
        `FAIL_UNLESS_EQUAL(payload[1].beat, 64'h0004_0005_0006_0007);

        packet.ramp(0);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 2);
        `FAIL_UNLESS_EQUAL(payload[0].beat, 64'h0008_0009_000A_000B);
        `FAIL_UNLESS_EQUAL(payload[1].beat, 64'h000C_000D_000E_000F);

        packet.ramp(0);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 2);
        `FAIL_UNLESS_EQUAL(payload[0].beat, 64'h0010_0011_0012_0013);
        `FAIL_UNLESS_EQUAL(payload[1].beat, 64'h0014_0015_0016_0017);

        packet.ramp(1);
        payload = packet.get_payload();
        `FAIL_UNLESS_EQUAL(payload.size(), 2);
        `FAIL_UNLESS_EQUAL(payload[0].beat, 64'h0000_0001_0002_0003);
        `FAIL_UNLESS_EQUAL(payload[1].beat, 64'h0004_0005_0006_0007);
        
    `SVTEST_END


    `SVTEST(drat_extended_copy_packet_1)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;
        logic [63:0] raw_header;

        raw_header = {PACKET_TYPE, TEST_SEQ_ID, 16'd32, TEST_FLOW_ID};

        fork
            // writer
            begin
                extended_stream.axis.write_beat(raw_header, 0);
                extended_stream.axis.write_beat(TEST_TIMESTAMP_BEAT, 0);
                extended_stream.axis.write_beat(TEST_MIMO_BEAT, 0);
                extended_stream.axis.write_beat(TEST_PAYLOAD_0, 1);
            end

            // receiver (packet read beats from stream, fill packet itself)
            begin
                packet.copy_to_pkt(extended_stream);
            end
        join

        payload = packet.get_payload();

        `FAIL_UNLESS_EQUAL(packet.get_header(), {raw_header, TEST_TIMESTAMP_BEAT, TEST_MIMO_BEAT});
        `FAIL_UNLESS_EQUAL(payload.size(), 1)
        `FAIL_UNLESS_EQUAL(payload[0].beat, TEST_PAYLOAD_0)

    `SVTEST_END

    `SVTEST(drat_extended_copy_packet_2)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;
        logic [63:0] raw_header;

        raw_header = {PACKET_TYPE, TEST_SEQ_ID, 16'd40, TEST_FLOW_ID};

        fork
            // writer
            begin
                extended_stream.axis.write_beat(raw_header, 0);
                extended_stream.axis.write_beat(TEST_TIMESTAMP_BEAT, 0);
                extended_stream.axis.write_beat(TEST_MIMO_BEAT, 0);
                extended_stream.axis.write_beat(TEST_PAYLOAD_0, 0);
                extended_stream.axis.write_beat(TEST_PAYLOAD_1, 1);
            end

            // receiver (packet read beats from stream, fill packet itself)
            begin
                packet.copy_to_pkt(extended_stream);
            end
        join

        payload = packet.get_payload();

        `FAIL_UNLESS_EQUAL(packet.get_header(), {raw_header, TEST_TIMESTAMP_BEAT, TEST_MIMO_BEAT});
        `FAIL_UNLESS_EQUAL(payload.size(), 2)
        `FAIL_UNLESS_EQUAL(payload[0].beat, TEST_PAYLOAD_0)
        `FAIL_UNLESS_EQUAL(payload[1].beat, TEST_PAYLOAD_1)

    `SVTEST_END

    `SVTEST(drat_extended_same)
        DRaTPacketExtended packet_1 = new();
        DRaTPacketExtended packet_2 = new();
        pkt_header_extended_t header;
        
        header = '0;
        header.packet_type = PACKET_TYPE;
        header.seq_id = TEST_SEQ_ID;
        header.length = 16'd40;
        header.flow_id = TEST_FLOW_ID;
        header.timestamp = TEST_TIMESTAMP_BEAT;
        header.rx_mimo_metadata = TEST_MIMO_BEAT;

        packet_1.set_header(header);
        //packet_1.reset_payload(2);
        packet_1.allocate_payload();
        packet_1.rewind_payload();
        packet_1.set_beat(TEST_PAYLOAD_0);
        packet_1.set_beat(TEST_PAYLOAD_1);

        packet_2.set_header(header);
        //packet_2.reset_payload(2);
        packet_2.allocate_payload();
        packet_2.rewind_payload();
        packet_2.set_beat(TEST_PAYLOAD_0);
        packet_2.set_beat(TEST_PAYLOAD_1);

        `FAIL_UNLESS_EQUAL(packet_1.get_payload[0], packet_2.get_payload[0]);
        `FAIL_UNLESS_EQUAL(packet_1.get_payload[1], packet_2.get_payload[1]);
        `FAIL_UNLESS(packet_1.is_same(packet_2, 0) === 1'b1);
        //`FAIL_UNLESS(packet_1.is_same(packet_2, 1) === 1'b1);

        packet_2.set_rx_mimo_metadata(~TEST_MIMO_BEAT);
        `FAIL_UNLESS(packet_1.is_same(packet_2, 0) === 1'b0);
        //`FAIL_UNLESS(packet_1.is_same(packet_2, 1) === 1'b1);

        packet_2.set_rx_mimo_metadata(TEST_MIMO_BEAT);
        packet_2.rewind_payload();
        packet_2.set_beat(TEST_PAYLOAD_0);
        packet_2.set_beat(64'h0000_0000_0000_0000);
        `FAIL_UNLESS(packet_1.is_same(packet_2, 0) === 1'b0);
        //`FAIL_UNLESS(packet_1.is_same(packet_2, 1) === 1'b1);
        
        packet_2.reset_payload(1);
        `FAIL_UNLESS(packet_1.is_same(packet_2, 0) === 1'b0);

    `SVTEST_END

    //=========================================================================
    // AXIS interface utility tests
    //=========================================================================
    // Push full packet
    //-------------------------------------------------------------------------
    `SVTEST(drat_extended_push_packet_1)
        DRaTPacketExtended packet = new();
        pkt_header_extended_t header;
        logic [63:0] observed_data [0:3];
        logic observed_last [0:3];
        
        header = '0;
        header.packet_type = PACKET_TYPE;
        header.seq_id = TEST_SEQ_ID;
        header.length = 16'd32;
        header.flow_id = TEST_FLOW_ID;
        header.timestamp = TEST_TIMESTAMP_BEAT;
        header.rx_mimo_metadata = TEST_MIMO_BEAT;

        packet.set_header(header);
        packet.allocate_payload();
        packet.rewind_payload();
        packet.set_beat(TEST_PAYLOAD_0);

        fork
            // writer
            begin
                extended_stream.push_pkt(packet);
            end

            // receiver
            begin
                for ( integer i = 0; i < 4; i++ ) begin
                   extended_stream.axis.read_beat(observed_data[i], observed_last[i]); 
                end
            end
        join

        `FAIL_UNLESS_EQUAL(observed_data[0], {PACKET_TYPE, TEST_SEQ_ID, 16'd32, TEST_FLOW_ID});
        `FAIL_UNLESS_EQUAL(observed_last[0], 1'b0);

        `FAIL_UNLESS_EQUAL(observed_data[1], TEST_TIMESTAMP_BEAT);
        `FAIL_UNLESS_EQUAL(observed_last[1], 1'b0);

        `FAIL_UNLESS_EQUAL(observed_data[2], TEST_MIMO_BEAT);
        `FAIL_UNLESS_EQUAL(observed_last[2], 1'b0);

        `FAIL_UNLESS_EQUAL(observed_data[3], TEST_PAYLOAD_0);
        `FAIL_UNLESS_EQUAL(observed_last[3], 1'b1);

    `SVTEST_END

    `SVTEST(drat_extended_push_packet_2)
        DRaTPacketExtended packet = new();
        pkt_header_extended_t header;
        logic [63:0] observed_data [0:4];
        logic observed_last [0:4];
        
        header = '0;
        header.packet_type = PACKET_TYPE;
        header.seq_id = TEST_SEQ_ID;
        header.length = 16'd40;
        header.flow_id = TEST_FLOW_ID;
        header.timestamp = TEST_TIMESTAMP_BEAT;
        header.rx_mimo_metadata = TEST_MIMO_BEAT;

        packet.set_header(header);
        packet.allocate_payload();
        packet.rewind_payload();
        packet.set_beat(TEST_PAYLOAD_0);
        packet.set_beat(TEST_PAYLOAD_1);

        fork
            // writer
            begin
                extended_stream.push_pkt(packet);
            end

            // receiver
            begin
                for ( integer i = 0; i < 5; i++ ) begin
                   extended_stream.axis.read_beat(observed_data[i], observed_last[i]); 
                end
            end
        join

        `FAIL_UNLESS_EQUAL(observed_data[0], {PACKET_TYPE, TEST_SEQ_ID, 16'd40, TEST_FLOW_ID});
        `FAIL_UNLESS_EQUAL(observed_last[0], 1'b0);

        `FAIL_UNLESS_EQUAL(observed_data[1], TEST_TIMESTAMP_BEAT);
        `FAIL_UNLESS_EQUAL(observed_last[1], 1'b0);

        `FAIL_UNLESS_EQUAL(observed_data[2], TEST_MIMO_BEAT);
        `FAIL_UNLESS_EQUAL(observed_last[2], 1'b0);

        `FAIL_UNLESS_EQUAL(observed_data[3], TEST_PAYLOAD_0);
        `FAIL_UNLESS_EQUAL(observed_last[3], 1'b0);

        `FAIL_UNLESS_EQUAL(observed_data[4], TEST_PAYLOAD_1);
        `FAIL_UNLESS_EQUAL(observed_last[4], 1'b1);

    `SVTEST_END

    //-------------------------------------------------------------------------
    // Push extended header
    //-------------------------------------------------------------------------
    `SVTEST(drat_extended_push_header)
        DRaTPacketExtended packet = new();
        pkt_header_extended_t header;
        logic [63:0] observed_data [0:2];
        logic observed_last [0:2];
        
        header = '0;
        header.packet_type = PACKET_TYPE;
        header.seq_id = TEST_SEQ_ID;
        header.length = 16'd40;
        header.flow_id = TEST_FLOW_ID;
        header.timestamp = TEST_TIMESTAMP_BEAT;
        header.rx_mimo_metadata = TEST_MIMO_BEAT;

        packet.set_header(header);
        packet.allocate_payload();
        packet.rewind_payload();
        packet.set_beat(TEST_PAYLOAD_0);

        fork
            // writer
            begin
                extended_stream.push_header(header);
            end

            // receiver
            begin
                for ( integer i = 0; i < 3; i++ ) begin
                   extended_stream.axis.read_beat(observed_data[i], observed_last[i]); 
                end
            end
        join

        `FAIL_UNLESS_EQUAL(observed_data[0], {PACKET_TYPE, TEST_SEQ_ID, 16'd40, TEST_FLOW_ID});
        `FAIL_UNLESS_EQUAL(observed_last[0], 1'b0);

        `FAIL_UNLESS_EQUAL(observed_data[1], TEST_TIMESTAMP_BEAT);
        `FAIL_UNLESS_EQUAL(observed_last[1], 1'b0);

        `FAIL_UNLESS_EQUAL(observed_data[2], TEST_MIMO_BEAT);
        `FAIL_UNLESS_EQUAL(observed_last[2], 1'b0);

    `SVTEST_END

    //-------------------------------------------------------------------------
    // Pop extended packet
    //-------------------------------------------------------------------------
    `SVTEST(drat_extended_pop_packet_1)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;
        logic [63:0] raw_header;

        raw_header = {PACKET_TYPE, TEST_SEQ_ID, 16'd32, TEST_FLOW_ID};

        fork
            // writer
            begin
                extended_stream.axis.write_beat(raw_header, 0);
                extended_stream.axis.write_beat(TEST_TIMESTAMP_BEAT, 0);
                extended_stream.axis.write_beat(TEST_MIMO_BEAT, 0);
                extended_stream.axis.write_beat(TEST_PAYLOAD_0, 1);
            end

            // receiver (stream reads AXIS beats and fills in packet)
            begin
                extended_stream.pop_pkt(packet);
            end
        join

        payload = packet.get_payload();

        `FAIL_UNLESS_EQUAL(packet.get_header(), {raw_header, TEST_TIMESTAMP_BEAT, TEST_MIMO_BEAT});
        `FAIL_UNLESS_EQUAL(payload.size(), 1)
        `FAIL_UNLESS_EQUAL(payload[0].beat, TEST_PAYLOAD_0)

    `SVTEST_END

    `SVTEST(drat_extended_pop_packet_2)
        DRaTPacketExtended packet = new();
        pkt_payload_t payload;
        logic [63:0] raw_header;

        raw_header = {PACKET_TYPE, TEST_SEQ_ID, 16'd40, TEST_FLOW_ID};

        fork
            // writer
            begin
                extended_stream.axis.write_beat(raw_header, 0);
                extended_stream.axis.write_beat(TEST_TIMESTAMP_BEAT, 0);
                extended_stream.axis.write_beat(TEST_MIMO_BEAT, 0);
                extended_stream.axis.write_beat(TEST_PAYLOAD_0, 0);
                extended_stream.axis.write_beat(TEST_PAYLOAD_1, 1);
            end

            // receiver (stream reads AXIS beats and fills in packet)
            begin
                extended_stream.pop_pkt(packet);
            end
        join

        payload = packet.get_payload();

        `FAIL_UNLESS_EQUAL(packet.get_header(), {raw_header, TEST_TIMESTAMP_BEAT, TEST_MIMO_BEAT});
        `FAIL_UNLESS_EQUAL(payload.size(), 2)
        `FAIL_UNLESS_EQUAL(payload[0].beat, TEST_PAYLOAD_0)
        `FAIL_UNLESS_EQUAL(payload[1].beat, TEST_PAYLOAD_1)

    `SVTEST_END

    `SVUNIT_TESTS_END

endmodule
