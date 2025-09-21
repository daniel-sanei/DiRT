//-----------------------------------------------------------------------------
// File:    axis_rtspi.sv
//
// Author:  Ian Buckley, Ion Concepts LLC
//
// Parameterizable:
//
// Description:
// SPI Master interface with host side AXIS DRaT packet interfaces rather than
// a classic memory mapped bus (AXI4lite style). Each SPI transaction can be async
// (Happens upon packet ingress), or Synchronous (Happens when system time counter
// matches time metadata in packet). Pending synchronous transactions will cause
// organic AIXS backpressure upstream and form a blocking queue.
// NOTE: Fixed latency of 3 clk cycles between timestamp match and assertion of bb_s.
//
//-----------------------------------------------------------------------------
`default_nettype none
/*
 | clk         | 1      | I             | logic clock                                              |
| ----------- | ------ | ------------- | -------------------------------------------------------- |
| rst         | 1      | I             | logic reset                                              |
| in_axis     | 64     | axis_t.slave  | command packet bus                                       |
| out_axis    | 64b    | axis_t.master | response packet bus                                      |
| system_time | [63:0] | I             | System time in ticks                                     |
| sclk        | 1      | O             | SPI Clock                                                |
| ss_b        | 1      | O             | Slave Select (active low)                                |
| mosi        | 1      | O             | Master Out Slave In                                      |
| miso        | 1      | I             | Master In, Slave out                                     |
| sclk_div    | 8      | I             | CSR that sets integer divde for logic clock to SPI clock |
| enable      |        |               |                                                          |
 */

module axis_rtspi
  (
   input wire	     clk,
   input wire	     rst,
   // CSR (Control/Status Register) interface
   input wire	     csr_enable,
   input wire [7:0]  csr_sclk_div,
   // input logic [31:0] csr_flow_id_cmd, // Should we filter on FlowID?
   input wire [31:0] csr_flow_id_response,
   // System time
   input wire [63:0] system_time,
   // SPI electrical interface
   spi_t.master spi,
   // Command Bus
   axis_t.master in_axis,
   // Response Bus
   axis_t.master out_axis
   );

   import drat_protocol::*;
   import axis_rtspi_pkg::*;


   // States
   enum		     {
                      S_IDLE,
                      S_PARSE,
                      S_TIMECHECK,
		      S_TIMESKIP,
		      S_RW,
		      S_A14,
		      S_A13,
		      S_A12,
		      S_A11,
		      S_A10,
		      S_A9,
		      S_A8,
		      S_A7,
		      S_A6,
		      S_A5,
		      S_A4,
		      S_A3,
		      S_A2,
		      S_A1,
		      S_A0,
		      S_WAIT_RISING,
		      S_D7,
		      S_D6,
		      S_D5,
		      S_D4,
		      S_D3,
		      S_D2,
		      S_D1,
		      S_D0,
		      S_SELECT_HIGH,
		      S_SPI_CLOCK_INACTIVE,
		      S_RESP_HEADER,
		      S_RESP_TIME,
		      S_RESP_PAYLOAD,
		      S_DISCARD
                      } state;



   //-----------------------------------------------------------
   // Divide logic clock synchronously to form SCLK.
   // Mask output to I/O when not in an active transaction.
   //-----------------------------------------------------------
   logic [7:0]	     count;
   logic	     sclk_internal;
   logic	     sclk_rising, sclk_falling;
   logic [7:0]	     expected_seq_id;
   logic [7:0]	     received_seq_id;
   logic [7:0]	     response_seq_id;
   logic [15:0]	     error_codes;
   logic [7:0]	     data_read;
   logic	     active;

   /* 
    We want the SCLK generator to generate a constant high output when the clock is idle.
    We want a falling edge soon and *exactly* the same number of clock cycles every time active goes asserted.
    We want no short SCLK cycles that violate device sheet clock frequency.
    We want the clock to go back to idle high cleanly after a rising edge.
    */
   always_ff @(posedge clk)
     begin
	if (~csr_enable | rst | ~active) begin
	   count <= csr_sclk_div;
	   sclk_internal <= 1;
	   sclk_rising <= 0;
	   sclk_falling <= 0;
	end else begin
	   if (count < csr_sclk_div) begin
	      count <= count + 1;
	      sclk_rising <= 0;
	      sclk_falling <= 0;
	   end else begin
	      count = 0;
	      sclk_internal <= ~sclk_internal;
	      sclk_rising <= ~sclk_internal;
	      sclk_falling <= sclk_internal;
	   end
	end // else: !if(~csr_enable | rst | ~active)
	// This pipeline always propagates.
	spi.sclk <= sclk_internal;	
     end // always_ff @ (posedge clk)
   
	  
   always_ff @(posedge clk) begin
      // Simplfy state machine readability
      automatic drat_protocol::pkt_header_t drat_header = drat_protocol::populate_header_no_timestamp(in_axis.tdata);
      automatic axis_rtspi_pkg::rtspi_command_t rtspi_command = in_axis.tdata[55:32];
      if (rst) begin
         state <= S_IDLE;
	 spi.mosi <= 0;
	 spi.ss_b <= 1;
      end else begin
         case (state)
	   // Leave IDLE state when csr_enable asserted.
	   // Passing through the S_IDLE state implies a new RTSPI burst has started so
	   // expected seq_id is reset to 0x0.
	   S_IDLE: begin
	      expected_seq_id <= 0;
	      response_seq_id <= 0;
	      error_codes <= 0;
	      active <= 0;
	      spi.mosi <= 0;
	      spi.ss_b <= 1;
	      data_read <= 0;
	      out_axis.tdata <= 0;	      
	      out_axis.tvalid <= 0;
	      out_axis.tlast <= 0;
	      if (~csr_enable) begin
		 in_axis.tready <= 0;
		 state <= S_IDLE;
	      end else begin
		 in_axis.tready <= 1;
		 state <= S_PARSE;
	      end
	   end
	   // In a correctly running system, only the first beat of a DRaT packet is presented in this state.
	   S_PARSE: begin
	      active <= 0; // Should already be inactive but bullet proofing this.
	      received_seq_id <= drat_header.seq_id; // Need this later to populate response packet
	      // Drive Response bus to idle state
	      out_axis.tdata <= 0;
	      out_axis.tvalid <= 0;
	      out_axis.tlast <= 0;
	      if (in_axis.tvalid && drat_header.packet_type == SPI_COMMAND) begin
		 // 1st beat of expected synchronous command packet
		 state <= S_TIMECHECK;
		 in_axis.tready <= 0;
		 if (drat_header.seq_id != expected_seq_id) begin
		    // Seqid not what was expected, packet loss??? Flag error code and reset expected seqid
		    error_codes <= error_codes | SPI_SEQ_ERROR;
		 end
	      end else if (in_axis.tvalid && drat_header.packet_type == SPI_COMMAND_ASYNC) begin
		 // 1st beat of expected asynchronous command packet
		 state <= S_TIMESKIP;
		 in_axis.tready <= 1;
		 if (drat_header.seq_id != expected_seq_id) begin
		    // Seqid not what was expected, packet loss??? Flag error code and reset expected seqid
		    error_codes <= error_codes | SPI_SEQ_ERROR;		    
		 end 		   
	      end else if (in_axis.tvalid && in_axis.tlast) begin
		 // Unexpected packet type, packet fragement, packet missalignment etc with TLAST set (assume it really is last beat of packet). Discard.
		 if (csr_enable) begin
		    state <= S_PARSE;
		    in_axis.tready <= 1;
		 end else begin
		    state <= S_IDLE;
		    in_axis.tready <= 0;
		 end
		 error_codes <= 0;
	      end else if (in_axis.tvalid) begin
		 // Unexpected packet type, packet fragement, packet missalignment etc. Discard.
		 state <= S_DISCARD;
		 in_axis.tready <= 1;
	      end else begin
		 // In all other cases keep ready asserted.
		 in_axis.tready <= 1;
	      end
	   end
	   // For synchronous command packets we block here until the timestamp matches system time.
	   // If the timestamp is later than current system time then we will return SPI_LATE as the response status.
	   // Current implementation will still execute the SPI transaction if late.
	   S_TIMECHECK: begin
	      if (in_axis.tvalid && in_axis.tdata == system_time) begin
		 // Matched execution time
		 state <= S_TIMESKIP; // Transit through this state to signal tready to timestamp
		 in_axis.tready <= 1;
	      end else if (in_axis.tvalid &&  in_axis.tdata < system_time) begin
		 // Execution time already expired, we are late!
		 error_codes <= error_codes | SPI_LATE;
		 state <= S_TIMESKIP; // Transit through this state to signal tready to timestamp
		 in_axis.tready <= 1;
	      end else begin
		 // NOTE: No provision to timeout...we could be waiting here a loooong time at 64bits with bad time.
		 in_axis.tready <= 0;
	      end
	   end // case: S_TIMECHECK
	   // For an Async command packet, just need to read and discard the empty timestamp field.
	   // Also used to transit out of S_TIMECHECK to give one cycle with tready asserted.
	   S_TIMESKIP: begin
	      if (in_axis.tvalid) begin
		 state <= S_RW;
		 in_axis.tready <= 0;
		 active <= 1;
	      end else begin
		 in_axis.tready <= 1;
	      end
	   end
	   // Start reading command bits from DRaT payload.
	   // Go active so that falling edge is presented
	   S_RW: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      in_axis.tready <= 0; // Want this DRaT payload beat to sit here so we can can pull bits from it.
	      if (in_axis.tvalid && sclk_falling) begin		 
		 spi.mosi <= rtspi_command.SPI_RW;
		 state <= S_A14;
	      end
	   end
	   // Address bit14
	   S_A14: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A14;
		 state <= S_A13;
	      end
	   end
	   // Address bit13
	   S_A13: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A13;
		 state <= S_A12;
	      end
	   end
	   // Address bit12
	   S_A12: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A12;
		 state <= S_A11;
	      end
	   end
	   // Address bit11
	   S_A11: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A11;
		 state <= S_A10;
	      end
	   end
	   // Address bit10
	   S_A10: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A10;
		 state <= S_A9;
	      end
	   end
	   // Address bit9
	   S_A9: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A9;
		 state <= S_A8;
	      end
	   end
	   // Address bit8
	   S_A8: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A8;
		 state <= S_A7;
	      end
	   end
	   // Address bit7
	   S_A7: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A7;
		 state <= S_A6;
	      end
	   end
	   // Address bit6
	   S_A6: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A6;
		 state <= S_A5;
	      end
	   end
	   // Address bit5
	   S_A5: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A5;
		 state <= S_A4;
	      end
	   end
	   // Address bit4
	   S_A4: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A4;
		 state <= S_A3;
	      end
	   end
	   // Address bit3
	   S_A3: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A3;
		 state <= S_A2;
	      end
	   end
	   // Address bit2
	   S_A2: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A2;
		 state <= S_A1;
	      end
	   end
	   // Address bit1
	   S_A1: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A1;
		 state <= S_A0;
	      end
	   end
	   // Address bit0
	   S_A0: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_falling) begin
		 spi.mosi <= rtspi_command.SPI_A0;
		 if (rtspi_command.SPI_RW) begin // TRUE when read command.
		    state <= S_WAIT_RISING; // Wait a half SCLK cycle for a rising edge then stay rising edge aligned for a read		    
		 end else begin
		    state <= S_D7; // Stay falling edge aligned for a write
		 end
	      end
	   end // case: S_A0
	   // Burn half an SCLK cycle in this state to shift to rising edge sampling.
	   S_WAIT_RISING: begin
	      active <= 1;
	      spi.ss_b <= 0;
	      if (sclk_rising) begin
		 state <= S_D7; // Now transition to rising edge aligned read state sequence.
	      end
	   end
	   // Data bit 7 Read or Write
	   S_D7:begin
	      spi.ss_b <= 0;
	      active <= 1;
  	      if (sclk_rising && rtspi_command.SPI_RW) begin // TRUE when read command.
		 data_read[7] <= spi.miso;
		 state <= S_D6;
	      end else if (sclk_falling && ~rtspi_command.SPI_RW) begin // TRUE when write command.
		 spi.mosi <= rtspi_command.SPI_D7;
		 state <= S_D6;
	      end
	   end
	   // Data bit 6 Read or Write
	   S_D6:begin
	      spi.ss_b <= 0;
	      active <= 1;
  	      if (sclk_rising && rtspi_command.SPI_RW) begin // TRUE when read command.
		 data_read[6] <= spi.miso;
		 state <= S_D5;
	      end else if (sclk_falling && ~rtspi_command.SPI_RW) begin // TRUE when write command.
		 spi.mosi <= rtspi_command.SPI_D6;
		 state <= S_D5;
	      end
	   end
	   // Data bit 5 Read or Write
	   S_D5:begin
	      spi.ss_b <= 0;
	      active <= 1;
  	      if (sclk_rising && rtspi_command.SPI_RW) begin // TRUE when read command.
		 data_read[5] <= spi.miso;
		 state <= S_D4;
	      end else if (sclk_falling && ~rtspi_command.SPI_RW) begin // TRUE when write command.
		 spi.mosi <= rtspi_command.SPI_D5;
		 state <= S_D4;
	      end
	   end
	   // Data bit 4 Read or Write
	   S_D4:begin
	      spi.ss_b <= 0;
	      active <= 1;
  	      if (sclk_rising && rtspi_command.SPI_RW) begin // TRUE when read command.
		 data_read[4] <= spi.miso;
		 state <= S_D3;
	      end else if (sclk_falling && ~rtspi_command.SPI_RW) begin // TRUE when write command.
		 spi.mosi <= rtspi_command.SPI_D4;
		 state <= S_D3;
	      end
	   end
	   // Data bit 3 Read or Write
	   S_D3:begin
	      spi.ss_b <= 0;
	      active <= 1;
  	      if (sclk_rising && rtspi_command.SPI_RW) begin // TRUE when read command.
		 data_read[3] <= spi.miso;
		 state <= S_D2;
	      end else if (sclk_falling && ~rtspi_command.SPI_RW) begin // TRUE when write command.
		 spi.mosi <= rtspi_command.SPI_D3;
		 state <= S_D2;
	      end
	   end // case: S_D3
	   // Data bit 2 Read or Write
	   S_D2:begin
	      spi.ss_b <= 0;
	      active <= 1;
  	      if (sclk_rising && rtspi_command.SPI_RW) begin // TRUE when read command.
		 data_read[2] <= spi.miso;
		 state <= S_D1;
	      end else if (sclk_falling && ~rtspi_command.SPI_RW) begin // TRUE when write command.
		 spi.mosi <= rtspi_command.SPI_D2;
		 state <= S_D1;
	      end
	   end
	   // Data bit 1 Read or Write
	   S_D1:begin
	      spi.ss_b <= 0;
	      active <= 1;
  	      if (sclk_rising && rtspi_command.SPI_RW) begin // TRUE when read command.
		 data_read[1] <= spi.miso;
		 state <= S_D0;
	      end else if (sclk_falling && ~rtspi_command.SPI_RW) begin // TRUE when write command.
		 spi.mosi <= rtspi_command.SPI_D1;
		 state <= S_D0;
	      end
	   end // case: S_D1
	   // Data bit 0 Read or Write
	   S_D0:begin
	      spi.ss_b <= 0;
	      active <= 1;
  	      if (sclk_rising && rtspi_command.SPI_RW) begin // TRUE when read command.
		 data_read[0] <= spi.miso;
		 state <= S_SELECT_HIGH; // Half an SCLK cycle before bb_s should go high
	      end else if (sclk_falling && ~rtspi_command.SPI_RW) begin // TRUE when write command.
		 spi.mosi <= rtspi_command.SPI_D0;
		 state <= S_SELECT_HIGH; // Full SCLK cycle before bb_s should go high
	      end
	   end // case: S_D0
	   // Complete this SPI transaction by driving ss_b high at SCLK falling edge....
	   S_SELECT_HIGH: begin
	      active <= 1;
	      if (sclk_falling) begin
		 spi.ss_b <= 1;
		 spi.mosi <= 0;
		 state <= S_SPI_CLOCK_INACTIVE;
	      end
	      else begin
		 spi.ss_b <= 0;
	      end
	   end // case: S_SELECT_HIGH
	   // ...then taking the clock inactive (and high) at the subsequent rising edge)
	   S_SPI_CLOCK_INACTIVE: begin
	      if (sclk_rising) begin
		 active = 0;
		 out_axis.tdata <= {SPI_RESPONSE,response_seq_id,16'd24/*SIZE*/,csr_flow_id_response};
		 out_axis.tvalid <= 1;
		 out_axis.tlast <= 1'b0;
		 response_seq_id <= response_seq_id + 1; // Can increment now response header captured in output buffer
		 if (out_axis.tready) begin
		    state <= S_RESP_TIME;
		 end else begin
		    state <= S_RESP_HEADER;
		 end
	      end else begin // if (sclk_rising)
		 active <= 1;
	      end // else: !if(sclk_rising)
	   end
	   // To avoid having a seperate state machine that emits a DRaT resonse and is loosly couple
	   // with the state machine running the SPI master, with the potential veirification issues
	   // and corner caes that could cause, we directly emit the response packet in the same state machine.
	   // (We already emit the first beat as the last state completes to maximize performance)
	   S_RESP_HEADER: begin
	      active <= 0;
	      spi.ss_b <= 1;
	      if (out_axis.tready) begin
		 // Header passed downstream, move to time
		 state <= S_RESP_TIME;
	      end else begin
		 state <= S_RESP_HEADER;
	      end
	   end
	   S_RESP_TIME: begin
	      active <= 0;
	      spi.ss_b <= 1;
	      out_axis.tdata <= system_time;
	      out_axis.tvalid <= 1;
	      out_axis.tlast <= 1'b0;
	      if (out_axis.tready) begin
		 state <= S_RESP_PAYLOAD;
	      end else begin
		 state <= S_RESP_TIME;
	      end
	   end
	   S_RESP_PAYLOAD: begin
	      active <= 0;
	      spi.ss_b <= 1;
	      out_axis.tdata <= {24'd0,data_read[7:0],error_codes[15:0],expected_seq_id[7:0],received_seq_id[7:0]} ;
	      out_axis.tvalid <= 1;
	      out_axis.tlast <= 1;
	      if (out_axis.tready) begin
		 if (csr_enable) begin // Are we still enabled?
		    state <= S_PARSE;
		    in_axis.tready <= 1; // Ready to recieve next SPI_COMMAND
		 end else begin
		    state <= S_IDLE;
		 end
		 if (error_codes & SPI_SEQ_ERROR) begin
		    expected_seq_id <= received_seq_id + 1; // On seq_id error reset expected seq_id for next command
		 end else begin
		    expected_seq_id <= expected_seq_id + 1;
		 end
	      end else begin
		 state <= S_RESP_PAYLOAD;
	      end
	   end


	   // Discard beats until we see TLAST asserted indicating we regained packet alignment
	   // and flushed whatever we just rejected.
	   S_DISCARD: begin
	      active <= 0;
	      spi.ss_b <= 1;
	      error_codes <= 0;
	      in_axis.tready <= 1;
	      if (in_axis.tvalid && in_axis.tlast) begin
		 // Discard complete
		 if (csr_enable) begin
		    state <= S_PARSE;
		 end else begin
		    state <= S_IDLE;
		    in_axis.tready <= 0;
		 end
	      end
	   end // case: S_DISCARD
	 endcase // case (state)
      end // else: !if(rst)
   end
endmodule // axis_rtspi

`default_nettype wire
