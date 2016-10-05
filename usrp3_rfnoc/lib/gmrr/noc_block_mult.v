//
// Copyright 2015 Ettus Research LLC
//

module noc_block_mult #(
  parameter NOC_ID = 64'h6D75_6C74_0000_0000,
  parameter STR_SINK_FIFOSIZE = 11)
(
  input bus_clk, input bus_rst,
  input ce_clk, input ce_rst,
  input  [63:0] i_tdata, input  i_tlast, input  i_tvalid, output i_tready,
  output [63:0] o_tdata, output o_tlast, output o_tvalid, input  o_tready,
  output [63:0] debug
);

  localparam MTU = 10;

  /////////////////////////////////////////////////////////////
  //
  // RFNoC Shell
  //
  ////////////////////////////////////////////////////////////

  wire [63:0]   cmdout_tdata, ackin_tdata;
  wire          cmdout_tlast, cmdout_tvalid, cmdout_tready, ackin_tlast, ackin_tvalid, ackin_tready;

  wire [127:0]  str_sink_tdata;
  wire [1:0]    str_sink_tlast, str_sink_tvalid, str_sink_tready;

  wire [63:0]   str_src_tdata;
  wire          str_src_tlast, str_src_tvalid, str_src_tready;

  wire [31:0]   in_tdata[0:1];
  wire [127:0]  in_tuser[0:1];
  wire [1:0]    in_tlast, in_tvalid, in_tready;

  wire [31:0]   out_tdata;
  wire [127:0]  out_tuser, out_tuser_pre;
  wire          out_tlast, out_tvalid, out_tready;

  wire          clear_tx_seqnum;
  wire [15:0]   src_sid[0:1], next_dst_sid;

  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE({2{STR_SINK_FIFOSIZE[7:0]}}),
    .INPUT_PORTS(2),
    .OUTPUT_PORTS(1))
  noc_shell (
    .bus_clk(bus_clk), .bus_rst(bus_rst),
    .i_tdata(i_tdata), .i_tlast(i_tlast), .i_tvalid(i_tvalid), .i_tready(i_tready),
    .o_tdata(o_tdata), .o_tlast(o_tlast), .o_tvalid(o_tvalid), .o_tready(o_tready),
    // Compute Engine Clock Domain
    .clk(ce_clk), .reset(ce_rst),
    // Control Sink
    .set_data(), .set_addr(), .set_stb(),
    .rb_stb(2'b11), .rb_data(128'd0), .rb_addr(),
    // Control Source
    .cmdout_tdata(cmdout_tdata), .cmdout_tlast(cmdout_tlast), .cmdout_tvalid(cmdout_tvalid), .cmdout_tready(cmdout_tready),
    .ackin_tdata(ackin_tdata), .ackin_tlast(ackin_tlast), .ackin_tvalid(ackin_tvalid), .ackin_tready(ackin_tready),
    // Stream Sink
    .str_sink_tdata(str_sink_tdata), .str_sink_tlast(str_sink_tlast), .str_sink_tvalid(str_sink_tvalid), .str_sink_tready(str_sink_tready),
    // Stream Source
    .str_src_tdata(str_src_tdata), .str_src_tlast(str_src_tlast), .str_src_tvalid(str_src_tvalid), .str_src_tready(str_src_tready),
    .clear_tx_seqnum(clear_tx_seqnum), .src_sid({src_sid[1],src_sid[0]}), .next_dst_sid(next_dst_sid),
    .resp_in_dst_sid(/* Unused */), .resp_out_dst_sid(/* Unused */),
    .debug(debug));

  chdr_deframer deframer_inst_0 (
      .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
      .i_tdata(str_sink_tdata[63:0]), .i_tlast(str_sink_tlast[0]), .i_tvalid(str_sink_tvalid[0]), .i_tready(str_sink_tready[0]),
      .o_tdata(in_tdata[0]), .o_tuser(in_tuser[0]), .o_tlast(in_tlast[0]), .o_tvalid(in_tvalid[0]), .o_tready(in_tready[0]));
  chdr_deframer deframer_inst_1 (
      .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
      .i_tdata(str_sink_tdata[127:64]), .i_tlast(str_sink_tlast[1]), .i_tvalid(str_sink_tvalid[1]), .i_tready(str_sink_tready[1]),
      .o_tdata(in_tdata[1]), .o_tuser(in_tuser[1]), .o_tlast(in_tlast[1]), .o_tvalid(in_tvalid[1]), .o_tready(in_tready[1]));

  cmul cmul (
      .clk(ce_clk), .reset(ce_rst),
      .a_tdata(in_tdata[0]), .a_tlast(in_tlast[0]), .a_tvalid(in_tvalid[0]), .a_tready(in_tready[0]),
      .b_tdata(in_tdata[1]), .b_tlast(in_tlast[1]), .b_tvalid(in_tvalid[1]), .b_tready(in_tready[1]),
      .o_tdata(out_tdata), .o_tlast(out_tlast), .o_tvalid(out_tvalid), .o_tready(out_tready));

  cvita_hdr_modify cvita_hdr_modify (
      .header_in(in_tuser[0]),
      .header_out(out_tuser),
      .use_pkt_type(1'b0),  .pkt_type(),
      .use_has_time(1'b0),  .has_time(),
      .use_eob(1'b0),       .eob(),
      .use_seqnum(1'b0),    .seqnum(),
      .use_length(1'b0),    .length(),
      .use_src_sid(1'b1),   .src_sid(src_sid[0]),
      .use_dst_sid(1'b1),   .dst_sid(next_dst_sid),
      .use_vita_time(1'b0), .vita_time());

  chdr_framer #(
      .SIZE(MTU))
    framer (
      .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum),
      .i_tdata(out_tdata), .i_tuser(out_tuser), .i_tlast(out_tlast), .i_tvalid(out_tvalid), .i_tready(out_tready),
      .o_tdata(str_src_tdata), .o_tlast(str_src_tlast), .o_tvalid(str_src_tvalid), .o_tready(str_src_tready));

endmodule
