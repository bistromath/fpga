//
// Copyright 2015 GMRR
//

module noc_block_gain #(
  parameter NOC_ID = 64'hB00B_0000_0000_0000,
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
  localparam SR_NEXT_DST   = 128;
  localparam SR_AXI_CONFIG = 129;
  localparam SR_GAIN       = 192;
  localparam SR_READBACK   = 255;

  //----------------------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------------------

  // Set next destination in chain
  wire [15:0] next_dst;

  // Readback register address
  wire rb_addr;

  //gain to multiply by
  (* mark_debug = "true" *) wire [15:0] gain;

  // RFNoC Shell
  wire [31:0] set_data;
  wire [7:0]  set_addr;
  wire        set_stb;

  wire clear_tx_seqnum;

  wire [63:0] str_sink_tdata, str_src_tdata;
  wire str_sink_tlast, str_sink_tvalid, str_sink_tready;
  wire str_src_tlast, str_src_tvalid, str_src_tready;

  // AXI Wrapper
  (* mark_debug = "true" *) wire [31:0]  m_axis_data_tdata;
  (* mark_debug = "true" *) wire [31:0]  s_axis_data_tdata;
  wire [127:0] m_axis_data_tuser;
  wire m_axis_data_tlast, m_axis_data_tvalid, m_axis_data_tready;
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
  setting_reg #(
    .my_addr(SR_NEXT_DST),
    .width(16))
  sr_next_dst(
    .clk(ce_clk),
    .rst(ce_rst),
    .strobe(set_stb),
    .addr(set_addr),
    .in(set_data),
    .out(next_dst),
    .changed());

  // Readback registers
  setting_reg #(
    .my_addr(SR_READBACK),
    .width(1))
  sr_rdback (
    .clk(ce_clk),
    .rst(ce_rst),
    .strobe(set_stb),
    .addr(set_addr),
    .in(set_data),
    .out(rb_addr),
    .changed());

  // Sum length
  setting_reg #(
    .my_addr(SR_GAIN),
    .width(16))
  sr_gain(
    .clk(ce_clk),
    .rst(ce_rst),
    .strobe(set_stb),
    .addr(set_addr),
    .in(set_data),
    .out(gain),
    .changed());

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE))
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
    // Stream Source
    .str_src_tdata(str_src_tdata),
    .str_src_tlast(str_src_tlast),
    .str_src_tvalid(str_src_tvalid),
    .str_src_tready(str_src_tready),
    .clear_tx_seqnum(clear_tx_seqnum),
    .debug(debug));

  // AXI Wrapper - Convert RFNoC Shell interface into AXI stream interface
  axi_wrapper #(
    .SR_AXI_CONFIG_BASE(SR_AXI_CONFIG))
  axi_wrapper_inst (
    .clk(ce_clk),
    .reset(ce_rst),
    // RFNoC Shell
    .clear_tx_seqnum(clear_tx_seqnum),
    .next_dst(next_dst),
    .set_stb(set_stb),
    .set_addr(set_addr),
    .set_data(set_data),
    .i_tdata(str_sink_tdata),
    .i_tlast(str_sink_tlast),
    .i_tvalid(str_sink_tvalid),
    .i_tready(str_sink_tready),
    .o_tdata(str_src_tdata),
    .o_tlast(str_src_tlast),
    .o_tvalid(str_src_tvalid),
    .o_tready(str_src_tready),
    // Internal AXI streams
    .m_axis_data_tdata(m_axis_data_tdata),
    .m_axis_data_tuser(m_axis_data_tuser),
    .m_axis_data_tlast(m_axis_data_tlast),
    .m_axis_data_tvalid(m_axis_data_tvalid),
    .m_axis_data_tready(m_axis_data_tready),
    .s_axis_data_tdata(s_axis_data_tdata),
    .s_axis_data_tlast(s_axis_data_tlast),
    .s_axis_data_tvalid(s_axis_data_tvalid),
    .s_axis_data_tready(s_axis_data_tready),
    .m_axis_config_tdata(),
    .m_axis_config_tlast(),
    .m_axis_config_tvalid(),
    .m_axis_config_tready(1'b1));

  (* mark_debug = "true" *) wire [63:0] mult_tdata;
  wire mult_tready, mult_tvalid, mult_tlast;
  wire cplx_tready, real_tready;

  //natively this will treat the gain register as a fractional value.
  //mult.v pads the upper 5 bits of A with 5'b0, so we add 5 bits to the output
  mult_rc #(.WIDTH_REAL(16),
         .WIDTH_CPLX(16),
         .WIDTH_P(26),
         .DROP_TOP_P(10),
         .LATENCY(4),
         .CASCADE_OUT(0)) inst_mult (
      .clk(ce_clk),
      .reset(ce_rst),
      .cplx_tdata(m_axis_data_tdata),
      .cplx_tlast(m_axis_data_tlast),
      .cplx_tvalid(m_axis_data_tvalid),
      .cplx_tready(cplx_tready),
      .real_tdata(gain),
      .real_tlast(m_axis_data_tlast),
      .real_tready(real_tready),
      .real_tvalid(m_axis_data_tvalid),
      .p_tdata(mult_tdata),
      .p_tlast(mult_tlast),
      .p_tvalid(mult_tvalid),
      .p_tready(mult_tready));

  //looks like i'm six bits short. why?
  axi_round_and_clip_complex #(
      .WIDTH_IN(26),
      .WIDTH_OUT(16),
      .CLIP_BITS(2), //has nothing to do with scaling
      .FIFOSIZE(0)) inst_round (
   .clk(ce_clk),
   .reset(ce_rst),
   .i_tdata(mult_tdata),
   .i_tlast(mult_tlast),
   .i_tready(mult_tready),
   .i_tvalid(mult_tvalid),
   .o_tdata(s_axis_data_tdata),
   .o_tlast(s_axis_data_tlast),
   .o_tready(s_axis_data_tready),
   .o_tvalid(s_axis_data_tvalid));


  //----------------------------------------------------------------------------
  // Combinational Logic
  //----------------------------------------------------------------------------
  assign m_axis_data_tready = cplx_tready & real_tready;


  // Readback register values
  always @*
    case(rb_addr)
      1'd0    : rb_data <= gain;
      default : rb_data <= 64'h0BADC0DE0BADC0DE;
    endcase

endmodule
