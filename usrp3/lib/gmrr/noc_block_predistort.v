//
// Copyright 2015 GMRR
//

module noc_block_predistort #(
  parameter NOC_ID = 64'h6275_7474_7300_0000,
  parameter NUM_CHANNELS = 4,
  parameter STR_SINK_FIFOSIZE = 11)
(
  input bus_clk,
  input bus_rst,

  input ce_clk,
  input ce_rst,

  input [63:0] i_tdata,
  input i_tlast,
  input i_tvalid,
  output i_tready,

  output [63:0] o_tdata,
  output o_tlast,
  output o_tvalid,
  input  o_tready,

  output [63:0] debug);

  //----------------------------------------------------------------------------
  // Constants
  //----------------------------------------------------------------------------
  //
  //just some notes for nick: JP said radio-redo now has separate register banks
  //for each input stream.
  //
  //the predistorter block might be better done as a separate block for each
  //one (there are four in total) but there are concerns with how many blocks
  //you can instantiate in RFNoC -- you might already be running up against the
  //xbar limit (11). so let's do the original thing and use four channels on a single
  //block, which instantiates a 'predistorter' object four times.

  // Settings registers addresses
  localparam SR_NEXT_DST    = 128;
  localparam SR_AXI_CONFIG  = 129;
  localparam SR_READBACK    = 255;

  localparam NUM_PORTS      = NUM_CHANNELS / 2;


  //----------------------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------------------


  // RFNoC Shell
  wire [31:0]             set_data[0:NUM_PORTS-1];
  wire [7:0]              set_addr[0:NUM_PORTS-1];
  wire [NUM_PORTS-1:0] set_stb;
  reg [63:0] rb_data[0:NUM_PORTS-1];
  wire [7:0] rb_addr[0:NUM_PORTS-1];

  wire [63:0]   cmdout_tdata, ackin_tdata;
  wire          cmdout_tlast, cmdout_tvalid, cmdout_tready, ackin_tlast, ackin_tvalid, ackin_tready;

  wire [NUM_PORTS-1:0] clear_tx_seqnum;

  wire [63:0] str_sink_tdata;
  wire str_sink_tlast, str_sink_tvalid, str_sink_tready;

  wire [63:0] str_src_tdata[0:NUM_PORTS-1];
  wire [NUM_PORTS-1:0] str_src_tlast, str_src_tvalid, str_src_tready;

  wire [15:0] src_sid[0:NUM_PORTS-1];
  wire [15:0] resp_in_dst_sid;
  wire [15:0] resp_out_dst_sid[0:NUM_PORTS-1];

  // Set next destination in chain
  wire [15:0] next_dst[0:NUM_PORTS-1];

  // AXI Wrapper
  // input (sink) data
  wire [31:0]  in_tdata;
  wire [127:0] in_tuser;
  wire in_tlast, in_tvalid, in_tready;

  // predistorter output data (four of these)
  wire [15:0]  out_tdata[0:NUM_CHANNELS-1]; //this syntax is fucked.
  wire [NUM_CHANNELS-1:0] out_tlast, out_tvalid, out_tready;

  wire [127:0] out_tuser[0:NUM_PORTS-1]; //only two of these
  //----------------------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------------------

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE[7:0]),
    .INPUT_PORTS(1),
    .OUTPUT_PORTS(NUM_PORTS))
  noc_shell (
    .bus_clk(bus_clk),
    .bus_rst(bus_rst),
    .i_tdata(i_tdata),
    .i_tlast(i_tlast),
    .i_tvalid(i_tvalid),
    .i_tready(i_tready),
    .o_tdata(o_tdata),
    .o_tlast(o_tlast),
    .o_tvalid(o_tvalid),
    .o_tready(o_tready),
    // Computer Engine Clock Domain
    .clk(ce_clk),
    .reset(ce_rst),
    // Control Sink
    .set_data({set_data[1], set_data[0]}),
    .set_addr({set_addr[1], set_addr[0]}),
    .set_stb({set_stb[1], set_stb[0]}),
    .rb_data({rb_data[1], rb_data[0]}),
    .rb_stb({NUM_PORTS{1'b1}}),
    .rb_addr({rb_addr[1], rb_addr[0]}),
    // Control Source (unused)
    .cmdout_tdata(cmdout_tdata),
    .cmdout_tlast(cmdout_tlast),
    .cmdout_tvalid(cmdout_tvalid),
    .cmdout_tready(cmdout_tready),
    .ackin_tdata(ackin_tdata),
    .ackin_tlast(ackin_tlast),
    .ackin_tvalid(ackin_tvalid),
    .ackin_tready(ackin_tready),
    .resp_in_dst_sid({resp_in_dst_sid[1], resp_in_dst_sid[0]}),
    .resp_out_dst_sid({resp_out_dst_sid[1], resp_out_dst_sid[0]}),
    // Stream Sink
    .str_sink_tdata(str_sink_tdata),
    .str_sink_tlast(str_sink_tlast),
    .str_sink_tvalid(str_sink_tvalid),
    .str_sink_tready(str_sink_tready),
    // Stream Sources //TODO ideally should be parameterized for NUM_CHANNELS
    .str_src_tdata({str_src_tdata[1], str_src_tdata[0]}),
    .str_src_tlast(str_src_tlast),
    .str_src_tvalid(str_src_tvalid),
    .str_src_tready(str_src_tready),
    .src_sid({src_sid[1], src_sid[0]}),
    .next_dst_sid({next_dst[1], next_dst[0]}),
    .clear_tx_seqnum(clear_tx_seqnum),
    .debug(debug));

  assign ackin_tready = 1'b1;

  wire [NUM_CHANNELS*32-1:0] taps_tdata_flat;
  wire [15:0] taps_tdata[0:NUM_CHANNELS-1];
  wire [NUM_CHANNELS-1:0] taps_tlast;
  wire [NUM_CHANNELS-1:0] taps_tvalid;
  wire [NUM_CHANNELS-1:0] taps_tready;

  genvar p;
  generate
    for (p = 0; p < NUM_CHANNELS; p = p + 1) begin
       //note the +15 (vs. +31) such that we're only assigning the lower 16b.
       assign taps_tdata[p] = taps_tdata_flat[p*32+15:p*32];
       axi_fifo #(.WIDTH(17), .SIZE(8)) config_stream (
          .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
          .i_tdata({(set_addr[0] == (SR_AXI_CONFIG+2*p+1)),set_data[0][15:0]}),
          .i_tvalid(set_stb[0] & ((set_addr[0] == (SR_AXI_CONFIG+2*p))|(set_addr[0] == (SR_AXI_CONFIG+2*p+1)))),
          .i_tready(),
          .o_tdata({taps_tlast[p],taps_tdata[p]}),
          .o_tvalid(taps_tvalid[p]),
          .o_tready(taps_tready[p]),
          .occupied(), .space()
       );
    end
  endgenerate

  wire [31:0] mux_tdata[0:NUM_PORTS-1];
  wire [NUM_PORTS-1:0] mux_tlast, mux_tvalid, mux_tready;

   axi_wrapper #(
      .SIMPLE_MODE(0) /* Handle header internally */)
   axi_wrapper_inst (
      .clk(ce_clk), .reset(ce_rst),
      .clear_tx_seqnum(clear_tx_seqnum[0]),
      .next_dst(next_dst[0]),
      .set_stb(), .set_addr(), .set_data(),
      .i_tdata(str_sink_tdata), .i_tlast(str_sink_tlast), .i_tvalid(str_sink_tvalid), .i_tready(str_sink_tready),
      .o_tdata(str_src_tdata[0]), .o_tlast(str_src_tlast[0]), .o_tvalid(str_src_tvalid[0]), .o_tready(str_src_tready[0]),
      .m_axis_data_tdata(in_tdata),
      .m_axis_data_tlast(in_tlast),
      .m_axis_data_tvalid(in_tvalid),
      .m_axis_data_tready(in_tready),
      .m_axis_data_tuser(in_tuser),
      .s_axis_data_tdata(mux_tdata[0]),
      .s_axis_data_tlast(mux_tlast[0]),
      .s_axis_data_tvalid(mux_tvalid[0]),
      .s_axis_data_tready(mux_tready[0]),
      .s_axis_data_tuser(out_tuser[0]),
      .m_axis_config_tdata(),
      .m_axis_config_tlast(),
      .m_axis_config_tvalid(),
      .m_axis_config_tready(),
      .m_axis_pkt_len_tdata(),
      .m_axis_pkt_len_tvalid(),
      .m_axis_pkt_len_tready());

  genvar u;
  generate
    for (u = 1; u < NUM_PORTS; u = u + 1) begin
      axi_wrapper #(
         .SIMPLE_MODE(0) /* Handle header internally */)
      axi_wrapper_inst (
         .clk(ce_clk), .reset(ce_rst),
         .clear_tx_seqnum(clear_tx_seqnum[u]),
         .next_dst(next_dst[u]),
         .set_stb(), .set_addr(), .set_data(),
         .i_tdata(), .i_tlast(), .i_tvalid(), .i_tready(),
         .o_tdata(str_src_tdata[u]), .o_tlast(str_src_tlast[u]), .o_tvalid(str_src_tvalid[u]), .o_tready(str_src_tready[u]),
         .m_axis_data_tdata(),
         .m_axis_data_tlast(),
         .m_axis_data_tvalid(),
         .m_axis_data_tready(),
         .m_axis_data_tuser(),
         .s_axis_data_tdata(mux_tdata[u]),
         .s_axis_data_tlast(mux_tlast[u]),
         .s_axis_data_tvalid(mux_tvalid[u]),
         .s_axis_data_tready(mux_tready[u]),
         .s_axis_data_tuser(out_tuser[u]),
         .m_axis_config_tdata(),
         .m_axis_config_tlast(),
         .m_axis_config_tvalid(),
         .m_axis_config_tready(),
         .m_axis_pkt_len_tdata(),
         .m_axis_pkt_len_tvalid(),
         .m_axis_pkt_len_tready());
   end
  endgenerate

  genvar s;
  generate
    for (s = 0; s < NUM_PORTS; s = s + 1) begin
      // Handle headers
      cvita_hdr_modify cvita_hdr_modify_inst (
         .header_in(in_tuser),
         .header_out(out_tuser[s]),
         .use_pkt_type(1'b0),  .pkt_type(),
         .use_has_time(1'b0),  .has_time(),
         .use_eob(1'b0),       .eob(),
         .use_seqnum(1'b0),    .seqnum(),
         .use_length(1'b0),    .length(),
         .use_src_sid(1'b1),   .src_sid(src_sid[s]),
         .use_dst_sid(1'b1),   .dst_sid(next_dst[s]),
         .use_vita_time(1'b0), .vita_time());
    end
  endgenerate

  //you'll want to split that stream into four streams.
  wire [15:0] input_split_tdata[0:3];
  wire [3:0] input_split_tlast, input_split_tvalid, input_split_tready;
  split_stream #(.WIDTH(16), .ACTIVE_MASK({NUM_CHANNELS{1'b1}})) input_splitter (
     .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
     .i_tdata(in_tdata[31:16]), .i_tlast(in_tlast), .i_tvalid(in_tvalid), .i_tready(in_tready),
     .o0_tdata(input_split_tdata[0]), .o0_tlast(input_split_tlast[0]), .o0_tvalid(input_split_tvalid[0]), .o0_tready(input_split_tready[0]),
     .o1_tdata(input_split_tdata[1]), .o1_tlast(input_split_tlast[1]), .o1_tvalid(input_split_tvalid[1]), .o1_tready(input_split_tready[1]),
     .o2_tdata(input_split_tdata[2]), .o2_tlast(input_split_tlast[2]), .o2_tvalid(input_split_tvalid[2]), .o2_tready(input_split_tready[2]),
     .o3_tdata(input_split_tdata[3]), .o3_tlast(input_split_tlast[3]), .o3_tvalid(input_split_tvalid[3]), .o3_tready(input_split_tready[3])
  );

  genvar k;
  generate
    for(k = 0; k < NUM_CHANNELS; k = k + 1) begin
       //instantiate a predistorter
       //the predistorter operates on magnitudes, which come in here on the
       //I channel (bits 31-16). out_tdata is 32b wide but we only set the upper
       //16.
       predistort #(.WIDTH(16), .DEPTH(13)) predistort_inst (
          .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
          .i_tdata(input_split_tdata[k]), .i_tlast(input_split_tlast[k]), .i_tvalid(input_split_tvalid[k]), .i_tready(input_split_tready[k]),
          .o_tdata(out_tdata[k]), .o_tlast(out_tlast[k]), .o_tvalid(out_tvalid[k]), .o_tready(out_tready[k]),
          .taps_tdata(taps_tdata[k]), .taps_tlast(taps_tlast[k]), .taps_tvalid(taps_tvalid[k]), .taps_tready(taps_tready[k])
       );
    end
  endgenerate

  //now we combine the streams back into two complex streams.
  //we can guarantee that the streams are aligned, right?
  join_complex #(.WIDTH(16)) join_complex_inst_0 (
    .ii_tdata(out_tdata[0]),
    .ii_tvalid(out_tvalid[0]),
    .ii_tready(out_tready[0]),
    .ii_tlast(out_tlast[0]),
    .iq_tdata(out_tdata[1]),
    .iq_tvalid(out_tvalid[1]),
    .iq_tready(out_tready[1]),
    .iq_tlast(out_tlast[1]),
    .o_tdata(mux_tdata[0]),
    .o_tvalid(mux_tvalid[0]),
    .o_tready(mux_tready[0]),
    .o_tlast(mux_tlast[0]));


  join_complex #(.WIDTH(16)) join_complex_inst_1 (
    .ii_tdata(out_tdata[3]),
    .ii_tvalid(out_tvalid[3]),
    .ii_tready(out_tready[3]),
    .ii_tlast(out_tlast[3]),
    .iq_tdata(out_tdata[2]),
    .iq_tvalid(out_tvalid[2]),
    .iq_tready(out_tready[2]),
    .iq_tlast(out_tlast[2]),
    .o_tdata(mux_tdata[1]),
    .o_tvalid(mux_tvalid[1]),
    .o_tready(mux_tready[1]),
    .o_tlast(mux_tlast[1]));

  // Readback register values
  // TODO load these up
  genvar y;
  generate
    for (y = 0; y < NUM_CHANNELS; y = y + 1) begin
     always @*
       case(rb_addr[y])
         default : rb_data[y] <= 64'hBEEEEEEEEEEEEEEF;
       endcase
    end
  endgenerate

endmodule
