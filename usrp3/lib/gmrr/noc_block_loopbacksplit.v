
//
// Copyright 2015 Ettus Research
//
module noc_block_loopbacksplit #(
  parameter NOC_ID = 64'h4655580000000000,
  parameter STR_SINK_FIFOSIZE = 11)
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
  wire [31:0] set_data[0:1];
  wire [7:0]  set_addr[0:1];
  wire [1:0]  set_stb;
  reg  [63:0] rb_data[0:1];
  wire [7:0]  rb_addr[0:1];

  wire [63:0] cmdout_tdata, ackin_tdata;
  wire        cmdout_tlast, cmdout_tvalid, cmdout_tready, ackin_tlast, ackin_tvalid, ackin_tready;

  wire [63:0] str_sink_tdata;
  wire        str_sink_tlast, str_sink_tvalid, str_sink_tready;
  wire [63:0] str_src_tdata[0:1];
  wire [1:0]  str_src_tlast, str_src_tvalid, str_src_tready;

  wire [15:0] src_sid[0:1];
  wire [15:0] next_dst_sid[0:1];
  wire [15:0] resp_out_dst_sid[0:1];
  wire [15:0] resp_in_dst_sid;

  wire [1:0]  clear_tx_seqnum;

  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE),
    .OUTPUT_PORTS(2))
  noc_shell (
    .bus_clk(bus_clk), .bus_rst(bus_rst),
    .i_tdata(i_tdata), .i_tlast(i_tlast), .i_tvalid(i_tvalid), .i_tready(i_tready),
    .o_tdata(o_tdata), .o_tlast(o_tlast), .o_tvalid(o_tvalid), .o_tready(o_tready),
    // Computer Engine Clock Domain
    .clk(ce_clk), .reset(ce_rst),
    // Control Sink
    .set_data({set_data[1], set_data[0]}),
    .set_addr({set_addr[1], set_addr[0]}),
    .set_stb({set_stb[1], set_stb[0]}),
    .rb_stb(2'b11),
    .rb_data({rb_data[1], rb_data[0]}),
    .rb_addr({rb_addr[1], rb_addr[0]}),
    // Control Source
    .cmdout_tdata(cmdout_tdata), .cmdout_tlast(cmdout_tlast), .cmdout_tvalid(cmdout_tvalid), .cmdout_tready(cmdout_tready),
    .ackin_tdata(ackin_tdata), .ackin_tlast(ackin_tlast), .ackin_tvalid(ackin_tvalid), .ackin_tready(ackin_tready),
    // Stream Sink
    .str_sink_tdata(str_sink_tdata), .str_sink_tlast(str_sink_tlast), .str_sink_tvalid(str_sink_tvalid), .str_sink_tready(str_sink_tready),
    // Stream Source
    .str_src_tdata({str_src_tdata[1], str_src_tdata[0]}),
    .str_src_tlast({str_src_tlast[1], str_src_tlast[0]}),
    .str_src_tvalid({str_src_tvalid[1], str_src_tvalid[0]}),
    .str_src_tready({str_src_tready[1], str_src_tready[0]}),
    // Stream IDs set by host
    .src_sid({src_sid[1], src_sid[0]}),                   // SID of this block
    .next_dst_sid({next_dst_sid[1], next_dst_sid[0]}),         // Next destination SID
    .resp_in_dst_sid(resp_in_dst_sid),   // Response destination SID for input stream responses / errors
    .resp_out_dst_sid({resp_out_dst_sid[1], resp_out_dst_sid[0]}), // Response destination SID for output stream responses / errors
    // Misc
    .vita_time('d0),
    .clear_tx_seqnum({clear_tx_seqnum[1], clear_tx_seqnum[0]}),
    .debug(debug));

  ////////////////////////////////////////////////////////////
  //
  // AXI Wrapper
  // Convert RFNoC Shell interface into AXI stream interface
  //
  ////////////////////////////////////////////////////////////
  wire [31:0]  m_axis_data_tdata;
  wire         m_axis_data_tlast;
  wire         m_axis_data_tvalid;
  wire         m_axis_data_tready;
  wire [127:0] m_axis_data_tuser;

  wire [31:0]  s_axis_data_tdata[0:1];
  wire         s_axis_data_tlast[0:1];
  wire         s_axis_data_tvalid[0:1];
  wire         s_axis_data_tready[0:1];
  wire [127:0] s_axis_data_tuser[0:1];

  chdr_deframer chdr_deframer_data (
     .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum[0]),
     .i_tdata(str_sink_tdata),
     .i_tlast(str_sink_tlast),
     .i_tvalid(str_sink_tvalid),
     .i_tready(str_sink_tready),
     .o_tdata(m_axis_data_tdata),
     .o_tlast(m_axis_data_tlast),
     .o_tvalid(m_axis_data_tvalid),
     .o_tready(m_axis_data_tready),
     .o_tuser(m_axis_data_tuser));

  //p sure because our block doesn't have delay
  //that i don't care about storing tuser in a fifo

  //Handle tuser headers
  cvita_hdr_modify cvita_hdr_modify_data (
     .header_in(m_axis_data_tuser),
     .header_out(s_axis_data_tuser[1]),
     .use_pkt_type(1'b0),  .pkt_type(),
     .use_has_time(1'b0),  .has_time(1'b0),
     .use_eob(1'b0),       .eob(),
     .use_seqnum(1'b0),    .seqnum(),
     .use_length(1'b0),    .length(),
     .use_src_sid(1'b1),   .src_sid(src_sid[1]),
     .use_dst_sid(1'b1),   .dst_sid(next_dst_sid[1]),
     .use_vita_time(1'b0), .vita_time());

  cvita_hdr_modify cvita_hdr_modify_ctrl (
     .header_in(m_axis_data_tuser),
     .header_out(s_axis_data_tuser[0]),
     .use_pkt_type(1'b0),  .pkt_type(),
     .use_has_time(1'b0),  .has_time(),
     .use_eob(1'b0),       .eob(),
     .use_seqnum(1'b0),    .seqnum(),
     .use_length(1'b0),    .length(),
     .use_src_sid(1'b1),   .src_sid(src_sid[0]),
     .use_dst_sid(1'b1),   .dst_sid(next_dst_sid[0]),
     .use_vita_time(1'b0), .vita_time());

  /* Simple Loopback on port 1 */
  assign m_axis_data_tready    = s_axis_data_tready[1] & s_axis_data_tready[0];
  assign s_axis_data_tvalid[1] = m_axis_data_tvalid;
  assign s_axis_data_tlast[1]  = m_axis_data_tlast;
  assign s_axis_data_tdata[1]  = m_axis_data_tdata;

  /* On port 0, what we want to do is send a single-sample packet to the
   * output for every input packet. We'll just set s_axis_data_tdata[0]
   * to some magic value (for debugging purposes) and then toggle tvalid only
   * when tlast is high (indicating the last sample of a packet).
   * chdr_framer inside the axi_wrapper will pinch off the turd when it sees
   * tlast high.
   */
  assign s_axis_data_tvalid[0] = m_axis_data_tvalid & m_axis_data_tlast;
  assign s_axis_data_tlast[0] = m_axis_data_tdata; //it's always the last sample of a packet
  assign s_axis_data_tdata[0] = 32'hDEAD_BEEF; //debug value

  chdr_framer #(.SIZE(10)) chdr_framer_data (
     .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum[1]),
     .i_tdata(s_axis_data_tdata[1]), .i_tuser(s_axis_data_tuser[1]),
     .i_tready(s_axis_data_tready[1]),
     .i_tlast(s_axis_data_tlast[1]), .i_tvalid(s_axis_data_tvalid[1]),
     .o_tdata(str_src_tdata[1]), .o_tlast(str_src_tlast[1]),
     .o_tvalid(str_src_tvalid[1]), .o_tready(str_src_tready[1]));

  chdr_framer #(.SIZE(2)) chdr_framer_ctrl (
     .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum[0]),
     .i_tdata(s_axis_data_tdata[0]), .i_tuser(s_axis_data_tuser[0]),
     .i_tlast(s_axis_data_tlast[0]), .i_tvalid(s_axis_data_tvalid[0]),
     .i_tready(s_axis_data_tready[0]),
     .o_tdata(str_src_tdata[0]), .o_tlast(str_src_tlast[0]),
     .o_tvalid(str_src_tvalid[0]), .o_tready(str_src_tready[0]));

  ////////////////////////////////////////////////////////////
  //
  // User code
  //
  ////////////////////////////////////////////////////////////
  // NoC Shell registers 0 - 127,
  // User register address space starts at 128
  localparam SR_USER_REG_BASE = 128;

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
  localparam [7:0] SR_TEST_REG_0 = SR_USER_REG_BASE;
  localparam [7:0] SR_TEST_REG_1 = SR_USER_REG_BASE + 8'd1;

  //we'll leave the test registers here just in case.
  wire [31:0] test_reg_0;
  setting_reg #(
    .my_addr(SR_TEST_REG_0), .awidth(8), .width(32))
  sr_test_reg_0 (
    .clk(ce_clk), .rst(ce_rst),
    .strobe(set_stb[0]), .addr(set_addr[0]), .in(set_data[0]), .out(test_reg_0), .changed());

  wire [31:0] test_reg_1;
  setting_reg #(
    .my_addr(SR_TEST_REG_1), .awidth(8), .width(32))
  sr_test_reg_1 (
    .clk(ce_clk), .rst(ce_rst),
    .strobe(set_stb[0]), .addr(set_addr[0]), .in(set_data[0]), .out(test_reg_1), .changed());

  // Readback registers
  // rb_stb set to 1'b1 on NoC Shell
  always @(posedge ce_clk) begin
    case(rb_addr[0])
      8'd0 : rb_data[0] <= {32'd0, test_reg_0};
      8'd1 : rb_data[0] <= {32'd0, test_reg_1};
      default : rb_data[0] <= 64'h0BADC0DE0BADC0DE;
    endcase
  end


endmodule
