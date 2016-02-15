
//
// Copyright 2017 Nick Foster
//
// Delays an input stream by some amount.
// Can both advance and retard delay (see delay_better.v).
// Can delay I relative to Q and vice versa. _tlast is asserted
// for either, so expect some short stub packets to be generated
// when delaying one channel relative to another. (I should look
// at this more closely).
// 
//
//`default_nettype none
module noc_block_delay #(
  parameter NOC_ID = 64'h64656C6179000000,
  parameter STR_SINK_FIFOSIZE = 11,
  parameter MAX_DIFF_DELAY_LOG2 = 10, //maximum differential delay between I and Q
  parameter MAX_DELAY_LOG2 = 16) //maximum delay (no FIFO so no performance impact here)
                                 //NB: don't set |delay_i-delay_q| > 2**MAX_DIFF_DELAY_LOG2
(
  input bus_clk, input bus_rst,
  input ce_clk, input ce_rst,
  input  [63:0] i_tdata, input  i_tlast, input  i_tvalid, output i_tready,
  output [63:0] o_tdata, output o_tlast, output o_tvalid, input  o_tready,
  output [63:0] debug
);

  ////////////////////////////////////////////////////////////
  //
  // RFNoC Shell
  //
  ////////////////////////////////////////////////////////////
  wire [31:0] set_data;
  wire [7:0]  set_addr;
  wire        set_stb;
  reg  [63:0] rb_data;
  wire [7:0]  rb_addr;

  wire [63:0] cmdout_tdata, ackin_tdata;
  wire        cmdout_tlast, cmdout_tvalid, cmdout_tready, ackin_tlast, ackin_tvalid, ackin_tready;

  wire [63:0] str_sink_tdata;
  wire        str_sink_tlast, str_sink_tvalid, str_sink_tready;
  wire [63:0] str_src_tdata;
  wire        str_src_tlast, str_src_tvalid, str_src_tready;

  wire [15:0] src_sid;
  wire [15:0] next_dst_sid;
  wire [15:0] resp_out_dst_sid;
  wire [15:0] resp_in_dst_sid;

  wire        clear_tx_seqnum;

  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE))
  noc_shell (
    .bus_clk(bus_clk), .bus_rst(bus_rst),
    .i_tdata(i_tdata), .i_tlast(i_tlast), .i_tvalid(i_tvalid), .i_tready(i_tready),
    .o_tdata(o_tdata), .o_tlast(o_tlast), .o_tvalid(o_tvalid), .o_tready(o_tready),
    // Computer Engine Clock Domain
    .clk(ce_clk), .reset(ce_rst),
    // Control Sink
    .set_data(set_data),
    .set_addr(set_addr),
    .set_stb(set_stb),
    .rb_stb(1'b1),
    .rb_data(rb_data),
    .rb_addr(rb_addr),
    // Control Source
    .cmdout_tdata(cmdout_tdata), .cmdout_tlast(cmdout_tlast), .cmdout_tvalid(cmdout_tvalid), .cmdout_tready(cmdout_tready),
    .ackin_tdata(ackin_tdata), .ackin_tlast(ackin_tlast), .ackin_tvalid(ackin_tvalid), .ackin_tready(ackin_tready),
    // Stream Sink
    .str_sink_tdata(str_sink_tdata), .str_sink_tlast(str_sink_tlast), .str_sink_tvalid(str_sink_tvalid), .str_sink_tready(str_sink_tready),
    // Stream Source
    .str_src_tdata(str_src_tdata),
    .str_src_tlast(str_src_tlast),
    .str_src_tvalid(str_src_tvalid),
    .str_src_tready(str_src_tready),
    // Stream IDs set by host
    .src_sid(src_sid),                   // SID of this block
    .next_dst_sid(next_dst_sid),         // Next destination SID
    .resp_in_dst_sid(resp_in_dst_sid),   // Response destination SID for input stream responses / errors
    .resp_out_dst_sid(resp_out_dst_sid), // Response destination SID for output stream responses / errors
    // Misc
    .vita_time(64'd0),
    .clear_tx_seqnum(clear_tx_seqnum),
    .debug(debug));

  ////////////////////////////////////////////////////////////
  //
  // AXI Wrapper
  // Convert RFNoC Shell interface into AXI stream interface
  //
  ////////////////////////////////////////////////////////////
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire [31:0]  m_axis_data_tdata;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire         m_axis_data_tlast;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire         m_axis_data_tvalid;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire         m_axis_data_tready;
  wire [127:0] m_axis_data_tuser;

  (* keep = "true",dont_touch="true",mark_debug="true" *) wire [31:0]  s_axis_data_tdata;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire         s_axis_data_tlast;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire         s_axis_data_tvalid;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire         s_axis_data_tready;
  wire [127:0] s_axis_data_tuser;

  //if we want to handle seqnum manually (because we're generating our own packets),
  //we can't use the axi_wrapper (it forces 1-to-1 seqnum in chdr_framer). so we have
  //to use chdr_deframer and chdr_framer.
  chdr_deframer inst_chdr_deframer (
    .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
    .i_tdata(str_sink_tdata), .i_tlast(str_sink_tlast), .i_tvalid(str_sink_tvalid), .i_tready(str_sink_tready),
    .o_tdata(m_axis_data_tdata), .o_tuser(), .o_tlast(m_axis_data_tlast), .o_tvalid(m_axis_data_tvalid), .o_tready(m_axis_data_tready));

  chdr_framer #(.SIZE(11), .USE_SEQ_NUM(0)) inst_chdr_framer(
    .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
    .i_tdata(s_axis_data_tdata), .i_tuser(s_axis_data_tuser), .i_tlast(s_axis_data_tlast), .i_tvalid(s_axis_data_tvalid), .i_tready(s_axis_data_tready),
    .o_tdata(str_src_tdata), .o_tlast(str_src_tlast), .o_tvalid(str_src_tvalid), .o_tready(str_src_tready));

  //now here we split, instantiate two delays, apply, and recombine
  //we have to use a split with FIFO because there's no guarantee our path
  //delays match

  (* keep = "true",dont_touch="true",mark_debug="true" *) wire [15:0] i_data_tdata, fuckery;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire i_data_tlast, i_data_tvalid, i_data_tready;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire [15:0] q_data_tdata;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire q_data_tlast, q_data_tvalid, q_data_tready;

  split_stream #(
    .WIDTH(32),
    .ACTIVE_MASK(4'b0011))
  split_stream_fifo_inst(
    .clk(ce_clk),
    .reset(ce_rst),
    .i_tdata(m_axis_data_tdata),
    .i_tlast(m_axis_data_tlast),
    .i_tvalid(m_axis_data_tvalid),
    .i_tready(m_axis_data_tready),
    .o0_tdata({i_data_tdata, fuckery}),
    .o0_tlast(i_data_tlast),
    .o0_tvalid(i_data_tvalid),
    .o0_tready(i_data_tready),
    .o1_tdata(q_data_tdata),
    .o1_tlast(q_data_tlast),
    .o1_tvalid(q_data_tvalid),
    .o1_tready(q_data_tready));

  (* keep = "true",dont_touch="true",mark_debug="true" *) wire [15:0] delayed_i_tdata;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire delayed_i_tlast, delayed_i_tvalid, delayed_i_tready;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire [15:0] delayed_q_tdata;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire delayed_q_tlast, delayed_q_tvalid, delayed_q_tready;

  (* keep = "true",dont_touch="true",mark_debug="true" *) wire [31:0] delay_i;
  (* keep = "true",dont_touch="true",mark_debug="true" *) wire [31:0] delay_q;

  delay_better #(
    .WIDTH(16),
    .MAX_LEN_LOG2(MAX_DELAY_LOG2))
  delay_i_inst(
    .clk(ce_clk),
    .reset(ce_rst),
    .i_tdata(i_data_tdata),
    .i_tlast(i_data_tlast),
    .i_tvalid(i_data_tvalid),
    .i_tready(i_data_tready),
    .o_tdata(delayed_i_tdata),
    .o_tlast(delayed_i_tlast),
    .o_tvalid(delayed_i_tvalid),
    .o_tready(delayed_i_tready),
    .len(delay_i[MAX_DELAY_LOG2-1:0]),
    .max_spp(16'b0));

  wire enable_diff;
  delay_better #(
    .WIDTH(16),
    .MAX_LEN_LOG2(MAX_DELAY_LOG2))
  delay_q_inst(
    .clk(ce_clk),
    .reset(ce_rst),
    .i_tdata(q_data_tdata),
    .i_tlast(q_data_tlast),
    .i_tvalid(q_data_tvalid),
    .i_tready(q_data_tready),
    .o_tdata(delayed_q_tdata),
    .o_tlast(delayed_q_tlast),
    .o_tvalid(delayed_q_tvalid),
    .o_tready(delayed_q_tready),
    .len(enable_diff ? delay_q[MAX_DELAY_LOG2-1:0] : delay_i[MAX_DELAY_LOG2-1:0]),
    .max_spp(16'b0));

  wire [15:0] buffered_i_tdata;
  wire buffered_i_tvalid, buffered_i_tlast, buffered_i_tready;
  wire [15:0] buffered_q_tdata;
  wire buffered_q_tvalid, buffered_q_tlast, buffered_q_tready;

  wire [31:0] joined_tdata;
  wire joined_tvalid, joined_tlast, joined_tready;

  axi_fifo #(.WIDTH(17), .SIZE(MAX_DELAY_LOG2)) i_buffer (
    .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
    .i_tdata({delayed_i_tlast, delayed_i_tdata}), .i_tvalid(delayed_i_tvalid), .i_tready(delayed_i_tready),
    .o_tdata({buffered_i_tlast, buffered_i_tdata}), .o_tvalid(buffered_i_tvalid), .o_tready(buffered_i_tready));

  axi_fifo #(.WIDTH(17), .SIZE(MAX_DELAY_LOG2)) q_buffer (
    .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
    .i_tdata({delayed_q_tlast, delayed_q_tdata}), .i_tvalid(delayed_q_tvalid), .i_tready(delayed_q_tready),
    .o_tdata({buffered_q_tlast, buffered_q_tdata}), .o_tvalid(buffered_q_tvalid), .o_tready(buffered_q_tready));

  wire all_here = buffered_i_tvalid & buffered_q_tvalid;
  wire int_tvalid = all_here;
  wire int_tready;
  assign buffered_i_tready = int_tready & all_here;
  assign buffered_q_tready = int_tready & all_here;

  //just to join the two streams
  axi_fifo_flop #(
    .WIDTH(33))
    out_fifo(
      .clk(ce_clk), .reset(ce_rst),
      .i_tdata({buffered_i_tlast | buffered_q_tlast, buffered_i_tdata, buffered_q_tdata}),
      .i_tvalid(int_tvalid),
      .i_tready(int_tready),
      .o_tdata({joined_tlast, joined_tdata}),
      .o_tvalid(joined_tvalid),
      .o_tready(joined_tready));

  // NoC Shell registers 0 - 127,
  // User register address space starts at 128
  localparam SR_USER_REG_BASE = 128;
  localparam [7:0] SR_DELAY_I = SR_USER_REG_BASE;
  localparam [7:0] SR_DELAY_Q = SR_USER_REG_BASE + 8'd1;
  localparam [7:0] SR_ENABLE_DIFF = SR_USER_REG_BASE + 8'd2;
  localparam [7:0] SR_PKT_SIZE = SR_USER_REG_BASE + 8'd3;

  //we aren't using m_axis_data_tuser at all, since we're regenerating the len and seqnums anyway.
  wire [127:0] new_tuser = {4'b0000, 12'b0, 16'd0, src_sid, next_dst_sid, 64'b0 };
  packet_resizer #(.SR_PKT_SIZE(SR_PKT_SIZE)) inst_packet_resizer(
    .clk(ce_clk),
    .reset(ce_rst),
    .next_dst_sid(next_dst_sid),
    .set_stb(set_stb), .set_addr(set_addr), .set_data(set_data),
    .i_tdata(joined_tdata),
    .i_tlast(1'b0),
    .i_tvalid(joined_tvalid),
    .i_tready(joined_tready),
    .i_tuser(new_tuser),
    .o_tdata(s_axis_data_tdata),
    .o_tlast(s_axis_data_tlast),
    .o_tvalid(s_axis_data_tvalid),
    .o_tready(s_axis_data_tready),
    .o_tuser(s_axis_data_tuser));

  ////////////////////////////////////////////////////////////
  //
  // User code
  //
  ////////////////////////////////////////////////////////////

  // Control Source Unused
  assign cmdout_tdata  = 64'd0;
  assign cmdout_tlast  = 1'b0;
  assign cmdout_tvalid = 1'b0;
  assign ackin_tready  = 1'b1;

  // Settings registers
  //
  // - The settings register bus is a simple strobed interface.
  // - Transactions include both a write and a readback.
  // - The write occurs when set_stb is asserted.
  //   The settings register with the address matching set_addr will
  //   be loaded with the data on set_data.
  // - Readback occurs when rb_stb is asserted. The read back strobe
  //   must assert at least one clock cycle after set_stb asserts /
  //   rb_stb is ignored if asserted on the same clock cycle of set_stb.
  //   Example valid and invalid timing:
  //              __    __    __    __
  //   clk     __|  |__|  |__|  |__|  |__
  //               _____
  //   set_stb ___|     |________________
  //                     _____
  //   rb_stb  _________|     |__________     (Valid)
  //                           _____
  //   rb_stb  _______________|     |____     (Valid)
  //           __________________________
  //   rb_stb                                 (Valid if readback data is a constant)
  //               _____
  //   rb_stb  ___|     |________________     (Invalid / ignored, same cycle as set_stb)
  //

  setting_reg #(
    .my_addr(SR_DELAY_I), .awidth(8), .width(32))
  sr_test_reg_0 (
    .clk(ce_clk), .rst(ce_rst),
    .strobe(set_stb), .addr(set_addr), .in(set_data), .out(delay_i), .changed());

  setting_reg #(
    .my_addr(SR_DELAY_Q), .awidth(8), .width(32))
  sr_test_reg_1 (
    .clk(ce_clk), .rst(ce_rst),
    .strobe(set_stb), .addr(set_addr), .in(set_data), .out(delay_q), .changed());

  setting_reg #(
    .my_addr(SR_ENABLE_DIFF), .awidth(8), .width(1))
  sr_test_reg_2 (
    .clk(ce_clk), .rst(ce_rst),
    .strobe(set_stb), .addr(set_addr), .in(set_data), .out(enable_diff), .changed());

  // Readback registers
  // rb_stb set to 1'b1 on NoC Shell
  always @(posedge ce_clk) begin
    case(rb_addr)
      8'd0 : rb_data <= {32'd0, delay_i};
      8'd1 : rb_data <= {32'd0, delay_q};
      8'd2 : rb_data <= {63'd0, enable_diff};
      default : rb_data <= 64'h0BADC0DE0BADC0DE;
    endcase
  end

endmodule
`default_nettype wire
