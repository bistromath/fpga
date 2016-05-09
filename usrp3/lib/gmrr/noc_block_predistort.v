//
// Copyright 2015 GMRR
//

module noc_block_predistort #(
  parameter NOC_ID = 64'h6275_7474_7300_0000,
  parameter NUM_CHANNELS = 1,
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


  //----------------------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------------------

  // Readback register address
  // Make this wide enough to handle all your readback regs
  wire [1:0] rb_addr;

  // RFNoC Shell
  wire [31:0]             set_data;
  wire [7:0]              set_addr;
  wire                    set_stb;

  wire [63:0]   cmdout_tdata, ackin_tdata;
  wire          cmdout_tlast, cmdout_tvalid, cmdout_tready, ackin_tlast, ackin_tvalid, ackin_tready;

  wire [NUM_CHANNELS-1:0] clear_tx_seqnum;

  wire [63:0] str_sink_tdata;
  wire str_sink_tlast, str_sink_tvalid, str_sink_tready;

  wire [63:0] str_src_tdata[0:NUM_CHANNELS-1];
  wire [64*NUM_CHANNELS-1:0] str_src_tdata_flat;
  genvar b;
  generate
    for (b = 0; b < NUM_CHANNELS; b = b + 1)
       assign str_src_tdata_flat[64*(b+1)-1:64*b] = str_src_tdata[b];
  endgenerate
  wire [NUM_CHANNELS-1:0] str_src_tlast, str_src_tvalid, str_src_tready;

  wire [15:0] src_sid;

  // Set next destination in chain
  wire [15:0] next_dst[0:NUM_CHANNELS-1];
  wire [16*NUM_CHANNELS-1:0] next_dst_flat;
  genvar c;
  generate
    for (c = 0; c < NUM_CHANNELS; c = c + 1)
       assign next_dst[c] = next_dst_flat[16*(c+1)-1:16*c];
 endgenerate

  // AXI Wrapper
  // input (sink) data
  wire [31:0]  in_tdata;
  wire [127:0] in_tuser;
  wire in_tlast, in_tvalid, in_tready;

  // output (source) data
  wire [31:0]  out_tdata[0:NUM_CHANNELS-1]; //this syntax is fucked.
  wire [127:0] out_tuser[0:NUM_CHANNELS-1];
  //we define these as four-wide so we can assign to them in the max case (four channels)
  wire [127:0] out_tuser_pre[0:3];
  wire [3:0] out_tlast, out_tvalid, out_tready;

  //----------------------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------------------
  // Readback register data
  reg [63:0] rb_data;

  //----------------------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------------------

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE),
    .INPUT_PORTS(1),
    .OUTPUT_PORTS(NUM_CHANNELS))
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
    .set_data(set_data),
    .set_addr(set_addr),
    .set_stb(set_stb),
    .rb_data(rb_data),
    .rb_stb({NUM_CHANNELS{1'b1}}),
    .rb_addr(rb_addr),
    // Control Source (unused)
    .cmdout_tdata(cmdout_tdata),
    .cmdout_tlast(cmdout_tlast),
    .cmdout_tvalid(cmdout_tvalid),
    .cmdout_tready(cmdout_tready),
    .ackin_tdata(ackin_tdata),
    .ackin_tlast(ackin_tlast),
    .ackin_tvalid(ackin_tvalid),
    .ackin_tready(ackin_tready),
    .resp_in_dst_sid(),
    .resp_out_dst_sid(),
    // Stream Sink
    .str_sink_tdata(str_sink_tdata),
    .str_sink_tlast(str_sink_tlast),
    .str_sink_tvalid(str_sink_tvalid),
    .str_sink_tready(str_sink_tready),
    // Stream Sources //TODO ideally should be parameterized for NUM_CHANNELS
    .str_src_tdata(str_src_tdata_flat),
    .str_src_tlast(str_src_tlast),
    .str_src_tvalid(str_src_tvalid),
    .str_src_tready(str_src_tready),
    .src_sid(src_sid),
    .next_dst_sid(next_dst_flat),
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
          .i_tdata({(set_addr == (SR_AXI_CONFIG+2*p+1)),set_data[15:0]}),
          .i_tvalid(set_stb & ((set_addr == (SR_AXI_CONFIG+2*p))|(set_addr == (SR_AXI_CONFIG+2*p+1)))),
          .i_tready(),
          .o_tdata({taps_tlast[p],taps_tdata[p]}),
          .o_tvalid(taps_tvalid[p]),
          .o_tready(taps_tready[p]),
          .occupied(), .space()
       );
    end
  endgenerate

  chdr_deframer chdr_deframer
    (.clk(ce_clk), .reset(ce_rst), .clear(1'b0),
     .i_tdata(str_sink_tdata), .i_tlast(str_sink_tlast), .i_tvalid(str_sink_tvalid), .i_tready(str_sink_tready),
     .o_tdata(in_tdata), .o_tuser(in_tuser), .o_tlast(in_tlast), .o_tvalid(in_tvalid), .o_tready(in_tready));

  //this causes a warning in synthesis because .o*_tlast is left blank
  split_stream_fifo #(.WIDTH(128), .ACTIVE_MASK({NUM_CHANNELS{1'b1}})) tuser_splitter (
       .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
       .i_tdata(in_tuser), .i_tlast(1'b0), .i_tvalid(in_tvalid & in_tlast), .i_tready(),
       .o0_tdata(out_tuser_pre[0]), .o0_tlast(), .o0_tvalid(), .o0_tready(out_tlast[0] & out_tready[0]),
       .o1_tdata(out_tuser_pre[1]), .o1_tlast(), .o1_tvalid(), .o1_tready(out_tlast[1] & out_tready[1]),
       .o2_tdata(out_tuser_pre[2]), .o2_tlast(), .o2_tvalid(), .o2_tready(out_tlast[2] & out_tready[2]),
       .o3_tdata(out_tuser_pre[3]), .o3_tlast(), .o3_tvalid(), .o3_tready(out_tlast[3] & out_tready[3])
  );

  //muck up your tuser streams
  genvar z;
  generate
    for(z = 0; z < NUM_CHANNELS; z = z + 1) begin
      assign out_tuser[z] = { out_tuser_pre[z][127:96], src_sid, next_dst[z], out_tuser_pre[z][63:0] };
    end
  endgenerate


  //you'll want to split that stream into four streams.
  wire [15:0] input_split_tdata[0:3];
  wire [3:0] input_split_tlast, input_split_tvalid, input_split_tready;
  split_stream #(.WIDTH(16), .ACTIVE_MASK({NUM_CHANNELS{1'b1}})) input_splitter (
     .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
     .i_tdata(in_tdata[15:0]), .i_tlast(in_tlast), .i_tvalid(in_tvalid), .i_tready(in_tready),
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
       //I channel (bits 15-0). out_tdata is 32b wide but we only set the low
       //16.
       predistort #(.WIDTH(16), .DEPTH(7)) predistort_inst (
          .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
          .i_tdata(input_split_tdata[k]), .i_tlast(input_split_tlast[k]), .i_tvalid(input_split_tvalid[k]), .i_tready(input_split_tready[k]),
          .o_tdata(out_tdata[k]), .o_tlast(out_tlast[k]), .o_tvalid(out_tvalid[k]), .o_tready(out_tready[k]),
          .taps_tdata(taps_tdata[k]), .taps_tlast(taps_tlast[k]), .taps_tvalid(taps_tvalid[k]), .taps_tready(taps_tready[k])
       );

       //put together a CHDR framer for the output
       chdr_framer #(.SIZE(10)) chdr_framer (
          .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum[k]),
          .i_tdata({16'b0, out_tdata[k][15:0]}), .i_tuser(out_tuser[k]), .i_tlast(out_tlast[k]), .i_tvalid(out_tvalid[k]), .i_tready(out_tready[k]),
          .o_tdata(str_src_tdata[k]), .o_tlast(str_src_tlast[k]), .o_tvalid(str_src_tvalid[k]), .o_tready(str_src_tready[k]));
    end
  endgenerate


  // Readback register values
  // TODO load these up
  always @*
    case(rb_addr)
      default : rb_data <= 64'hBEEEEEEEEEEEEEEF;
    endcase

endmodule
