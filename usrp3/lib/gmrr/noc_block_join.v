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

  // Set next destination in chain
  wire [15:0] next_dst;

  // Readback register address
  wire rb_addr;

  //Settings registers

  // RFNoC Shell
  wire [31:0] set_data;
  wire [7:0]  set_addr;
  wire        set_stb;

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
  reg [63:0] rb_data;

  //----------------------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------------------

  // Set next destination in chain
  setting_reg #(.my_addr(SR_NEXT_DST), .width(16))
  sr_next_dst0(.clk(ce_clk), .rst(ce_rst), .strobe(set_stb), .addr(set_addr), .in(set_data), .out(next_dst), .changed());

  // Readback registers
  setting_reg #(.my_addr(SR_READBACK), .width(1))
  sr_rdback (.clk(ce_clk), .rst(ce_rst), .strobe(set_stb), .addr(set_addr), .in(set_data), .out(rb_addr), .changed());

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE),
    .INPUT_PORTS(2),
    .OUTPUT_PORTS(1))
  noc_shell_inst (
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
    .clear_tx_seqnum(clear_tx_seqnum),
    .debug(debug));

  wire i_ready, q_ready;

  chdr_deframer deframer_i (
      .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
      .i_tdata(str_sink_tdata[63:0]), .i_tlast(str_sink_tlast[0]), .i_tvalid(str_sink_tvalid[0]), .i_tready(str_sink_tready[0]),
      .o_tdata(m_axis_data_tdata_i), .o_tuser(m_axis_data_tuser_i), .o_tlast(m_axis_data_tlast_i), .o_tvalid(m_axis_data_tvalid_i), .o_tready(m_axis_data_tready_i));

  chdr_deframer deframer_q (
      .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
      .i_tdata(str_sink_tdata[127:64]), .i_tlast(str_sink_tlast[1]), .i_tvalid(str_sink_tvalid[1]), .i_tready(str_sink_tready[1]),
      .o_tdata(m_axis_data_tdata_q), .o_tuser(m_axis_data_tuser_q), .o_tlast(m_axis_data_tlast_q), .o_tvalid(m_axis_data_tvalid_q), .o_tready(m_axis_data_tready_q));

  join_complex #(.WIDTH(16)) joiner (
      .ii_tdata(m_axis_data_tdata_i[31:16]), .ii_tlast(m_axis_data_tlast_i), .ii_tvalid(m_axis_data_tvalid_i), .ii_tready(m_axis_data_tready_i),
      .iq_tdata(m_axis_data_tdata_q[31:16]), .iq_tlast(m_axis_data_tlast_q), .iq_tvalid(m_axis_data_tvalid_q), .iq_tready(m_axis_data_tready_q),
      .o_tdata(s_axis_data_tdata), .o_tlast(s_axis_data_tlast), .o_tvalid(s_axis_data_tvalid), .o_tready(s_axis_data_tready));

  chdr_framer #(.SIZE(10)) framer (
      .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum),
      .i_tdata(s_axis_data_tdata),
      .i_tuser(s_axis_data_tuser),
      .i_tlast(s_axis_data_tlast),
      .i_tvalid(s_axis_data_tvalid),
      .i_tready(s_axis_data_tready),
      .o_tdata(str_src_tdata),
      .o_tlast(str_src_tlast),
      .o_tvalid(str_src_tvalid),
      .o_tready(str_src_tready));

  //----------------------------------------------------------------------------
  // Combinational Logic
  //----------------------------------------------------------------------------


  // Readback register values
  always @*
    case(rb_addr)
      default : rb_data <= 64'hBEEEEEEEEEEEEEEF;
    endcase

endmodule
