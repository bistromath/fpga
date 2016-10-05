//
// Copyright 2015 GMRR
//

module noc_block_join #(
  parameter NOC_ID = 64'h7733_0000_0000_0000,
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

  // Settings registers addresses
  localparam SR_NEXT_DST    = 128;
  localparam SR_READBACK    = 255;

  //----------------------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------------------

  // RFNoC Shell

  wire clear_tx_seqnum;

  wire [127:0] str_sink_tdata;
  wire [1:0] str_sink_tlast, str_sink_tvalid, str_sink_tready;

  wire [63:0] str_src_tdata;
  wire str_src_tlast, str_src_tvalid, str_src_tready;

  // AXI Wrapper
  // input (sink) data
  wire [31:0]  m_axis_data_tdata_i;
  wire [127:0] m_axis_data_tuser_i;
  wire m_axis_data_tlast_i, m_axis_data_tvalid_i, m_axis_data_tready_i;

  wire [31:0]  m_axis_data_tdata_q;
  wire [127:0] m_axis_data_tuser_q;
  wire m_axis_data_tlast_q, m_axis_data_tvalid_q, m_axis_data_tready_q;

  // output (source) data
  wire [31:0]  s_axis_data_tdata;
  wire [127:0] s_axis_data_tuser;
  wire s_axis_data_tlast, s_axis_data_tvalid, s_axis_data_tready;

  //----------------------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------------------

  // Readback register data
  //we define these flat 'cause we don't use them here anyway
  reg [127:0] rb_data;
  wire [15:0] rb_addr;
  wire [63:0] set_data;
  wire [15:0]  set_addr;
  wire [1:0]   set_stb;

  wire [15:0] src_sid[0:1];
  wire [15:0] next_dst_sid[0:1], resp_out_dst_sid[0:1];
  wire [15:0] resp_in_dst_sid[0:1];

  //----------------------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------------------

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE({2{STR_SINK_FIFOSIZE[7:0]}}),
    .INPUT_PORTS(2),
    .OUTPUT_PORTS(1))
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
    .rb_addr(rb_addr),
    .rb_stb(2'b1),
    // Control Source (unused)
    .cmdout_tdata(64'd0),
    .cmdout_tlast(1'b0),
    .cmdout_tvalid(1'b0),
    .cmdout_tready(),
    .ackin_tdata(),
    .ackin_tlast(),
    .ackin_tvalid(),
    .ackin_tready(1'b1),
    // Stream Sink
    .str_sink_tdata(str_sink_tdata),
    .str_sink_tlast(str_sink_tlast),
    .str_sink_tvalid(str_sink_tvalid),
    .str_sink_tready(str_sink_tready),
    // Stream Sources
    .str_src_tdata(str_src_tdata),
    .str_src_tlast(str_src_tlast),
    .str_src_tvalid(str_src_tvalid),
    .str_src_tready(str_src_tready),

    .src_sid({src_sid[1], src_sid[0]}),
    .next_dst_sid({next_dst_sid[1], next_dst_sid[0]}),
    .resp_in_dst_sid({resp_in_dst_sid[1], resp_in_dst_sid[0]}),
    .resp_out_dst_sid({resp_out_dst_sid[1], resp_out_dst_sid[0]}),

    .clear_tx_seqnum(clear_tx_seqnum),
    .debug(debug));

    chdr_deframer deframer_i (
      .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
      .i_tdata(str_sink_tdata[63:0]), .i_tlast(str_sink_tlast[0]), .i_tvalid(str_sink_tvalid[0]), .i_tready(str_sink_tready[0]),
      .o_tdata(m_axis_data_tdata_i), .o_tuser(m_axis_data_tuser_i), .o_tlast(m_axis_data_tlast_i), .o_tvalid(m_axis_data_tvalid_i), .o_tready(m_axis_data_tready_i));

    chdr_deframer deframer_q (
      .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
      .i_tdata(str_sink_tdata[127:64]), .i_tlast(str_sink_tlast[1]), .i_tvalid(str_sink_tvalid[1]), .i_tready(str_sink_tready[1]),
      .o_tdata(m_axis_data_tdata_q), .o_tuser(m_axis_data_tuser_q), .o_tlast(m_axis_data_tlast_q), .o_tvalid(m_axis_data_tvalid_q), .o_tready(m_axis_data_tready_q));

  //now we have two AXI streams, not aligned with each other, which need to be joined into a single stream.
  //join_complex works for aligned streams, but not for unaligned streams, so we need to first
  //buffer and align the two.

  wire [31:0] int_tdata = {m_axis_data_tdata_i[31:16], m_axis_data_tdata_q[31:16]};
  wire all_here = m_axis_data_tvalid_i & m_axis_data_tvalid_q;
  wire int_tvalid = all_here;
  wire int_tlast = m_axis_data_tlast_i | m_axis_data_tlast_q;
  wire int_tready;
  assign m_axis_data_tready_i = int_tready & all_here;
  assign m_axis_data_tready_q = int_tready & all_here;

  axi_fifo #(.WIDTH(33), .SIZE(1)) flop_output
     (.clk(ce_clk), .reset(ce_rst), .clear(1'b0),
      .i_tdata({int_tlast, int_tdata}), .i_tvalid(int_tvalid), .i_tready(int_tready),
      .o_tdata({s_axis_data_tlast, s_axis_data_tdata}), .o_tvalid(s_axis_data_tvalid), .o_tready(s_axis_data_tready));

  assign s_axis_data_tuser = { m_axis_data_tuser_i[127:96], src_sid[0], next_dst_sid[0], m_axis_data_tuser_i[63:0] };

    chdr_framer #(
      .SIZE(10))
    framer (
      .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum),
      .i_tdata(s_axis_data_tdata), .i_tuser(s_axis_data_tuser), .i_tlast(s_axis_data_tlast), .i_tvalid(s_axis_data_tvalid), .i_tready(s_axis_data_tready),
      .o_tdata(str_src_tdata), .o_tlast(str_src_tlast), .o_tvalid(str_src_tvalid), .o_tready(str_src_tready));

  //----------------------------------------------------------------------------
  // Combinational Logic
  //----------------------------------------------------------------------------

endmodule
