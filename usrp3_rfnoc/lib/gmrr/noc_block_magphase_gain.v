//
// Copyright 2015 GMRR
//

module noc_block_magphase_gain #(
  parameter NOC_ID = 64'h8844_0000_0000_0000,
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
  localparam SR_MAG_GAIN    = 192;
  localparam SR_PHASE_GAIN  = 193;

  //----------------------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------------------
  // Readback register address
  wire [7:0] rb_addr;
  wire [63:0] rb_data;

  // RFNoC Shell
  wire [31:0] set_data;
  wire [7:0]  set_addr;
  wire        set_stb;

  wire clear_tx_seqnum;

  wire [63:0] str_sink_tdata;
  wire str_sink_tlast, str_sink_tvalid, str_sink_tready;

  wire [63:0] str_src_tdata;
  wire str_src_tlast, str_src_tvalid, str_src_tready;

//  wire [63:0] cmdout_tdata, ackin_tdata;
//  wire        cmdout_tlast, cmdout_tvalid, cmdout_tready, ackin_tlast, ackin_tvalid, ackin_tready;

  wire [15:0] src_sid;
  wire [15:0] next_dst_sid, resp_out_dst_sid;
  wire [15:0] resp_in_dst_sid;

  // AXI Wrapper
  // input (sink) data
  wire [31:0]  m_axis_data_tdata;
  wire [127:0] m_axis_data_tuser;
  wire m_axis_data_tlast, m_axis_data_tvalid, m_axis_data_tready;

  // output (source) data
  wire [31:0]  s_axis_data_tdata;
  wire [127:0] s_axis_data_tuser;
  wire s_axis_data_tlast, s_axis_data_tvalid, s_axis_data_tready;

  //----------------------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------------------

  //----------------------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------------------
  //Settings registers
  wire [15:0] mag_gain;
  wire [15:0] phase_gain;

  setting_reg #(.my_addr(SR_MAG_GAIN), .width(16)) sr_mag_gain(
    .clk(ce_clk), .rst(ce_rst), .strobe(set_stb), .addr(set_addr), .in(set_data), .out(mag_gain), .changed());

  setting_reg #(.my_addr(SR_PHASE_GAIN), .width(16)) sr_phase_gain(
    .clk(ce_clk), .rst(ce_rst), .strobe(set_stb), .addr(set_addr), .in(set_data), .out(phase_gain), .changed());

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE),
    .INPUT_PORTS(1),
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
    .rb_stb(1'b1),
    .rb_addr(rb_addr),
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
    // Stream IDs
    .src_sid(src_sid),
    .next_dst_sid(next_dst_sid),
    .resp_in_dst_sid(resp_in_dst_sid),
    .resp_out_dst_sid(resp_out_dst_sid),
    .debug(debug));

  // AXI Wrapper - Convert RFNoC Shell interface into AXI stream interface
  axi_wrapper #(
    //.SR_AXI_CONFIG_BASE(SR_AXI_CONFIG)
  )
  axi_wrapper (
    .clk(ce_clk),
    .reset(ce_rst),
    // RFNoC Shell
    .clear_tx_seqnum(clear_tx_seqnum),
    .next_dst(next_dst_sid),
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

  wire [31:0] magphase_axis_data_tdata;
  wire magphase_axis_data_tlast;
  wire magphase_axis_data_tready;
  wire magphase_axis_data_tvalid;
  wire [15:0] magnitude_axis_data_tdata;
  wire magnitude_axis_data_tlast;
  wire magnitude_axis_data_tready;
  wire magnitude_axis_data_tvalid;
  wire [15:0] phase_axis_data_tdata;
  wire phase_axis_data_tlast;
  wire phase_axis_data_tready;
  wire phase_axis_data_tvalid;

  //this goes from SC16 I,Q to SC16 M,P
  complex_to_magphase inst_complex_to_magphase (
     .aclk(ce_clk),
     .aresetn(~ce_rst),
     .s_axis_cartesian_tdata(m_axis_data_tdata),
     .s_axis_cartesian_tlast(m_axis_data_tlast),
     .s_axis_cartesian_tready(m_axis_data_tready),
     .s_axis_cartesian_tvalid(m_axis_data_tvalid),
     .m_axis_dout_tdata(magphase_axis_data_tdata),
     .m_axis_dout_tlast(magphase_axis_data_tlast),
     .m_axis_dout_tready(magphase_axis_data_tready),
     .m_axis_dout_tvalid(magphase_axis_data_tvalid));

  //so we split the output into two 16bit streams
  split_complex #(.WIDTH(16)) inst_split_complex (
     .i_tdata(magphase_axis_data_tdata),
     .i_tlast(magphase_axis_data_tlast),
     .i_tvalid(magphase_axis_data_tvalid),
     .i_tready(magphase_axis_data_tready),
     .oq_tdata(magnitude_axis_data_tdata),
     .oq_tlast(magnitude_axis_data_tlast),
     .oq_tvalid(magnitude_axis_data_tvalid),
     .oq_tready(magnitude_axis_data_tready),
     .oi_tdata(phase_axis_data_tdata),
     .oi_tlast(phase_axis_data_tlast),
     .oi_tvalid(phase_axis_data_tvalid),
     .oi_tready(phase_axis_data_tready));

  //and multiply each of them by their respective gains
  (* mark_debug = "true" *) wire [25:0] mag_gained_axis_tdata;
  (* mark_debug = "true" *) wire mag_gained_axis_tlast, mag_gained_axis_tvalid, mag_gained_axis_tready;

  wire [25:0] phase_gained_axis_tdata;
  wire phase_gained_axis_tlast, phase_gained_axis_tvalid, phase_gained_axis_tready;

  (* mark_debug = "true" *) wire mag_gain_a_tready, mag_gain_b_tready;
  assign magnitude_axis_data_tready = mag_gain_a_tready & mag_gain_b_tready;

  wire phase_gain_a_tready, phase_gain_b_tready;
  assign phase_axis_data_tready = phase_gain_a_tready & phase_gain_b_tready;

  mult #(.WIDTH_A(16), .WIDTH_B(16), .WIDTH_P(26), .DROP_TOP_P(10)) inst_mag_gain(
      .clk(ce_clk),
      .reset(ce_rst),
      .a_tdata(magnitude_axis_data_tdata),
      .a_tlast(magnitude_axis_data_tlast),
      .a_tvalid(magnitude_axis_data_tvalid),
      .a_tready(mag_gain_a_tready),
      .b_tdata(mag_gain),
      .b_tlast(magnitude_axis_data_tlast),
      .b_tvalid(magnitude_axis_data_tvalid),
      .b_tready(mag_gain_b_tready),
      .p_tdata(mag_gained_axis_tdata),
      .p_tlast(mag_gained_axis_tlast),
      .p_tvalid(mag_gained_axis_tvalid),
      .p_tready(mag_gained_axis_tready));

  mult #(.WIDTH_A(16), .WIDTH_B(16), .WIDTH_P(26), .DROP_TOP_P(10)) inst_phase_gain(
      .clk(ce_clk),
      .reset(ce_rst),
      .a_tdata(phase_axis_data_tdata),
      .a_tlast(phase_axis_data_tlast),
      .a_tvalid(phase_axis_data_tvalid),
      .a_tready(phase_gain_a_tready),
      .b_tdata(phase_gain),
      .b_tlast(phase_axis_data_tlast),
      .b_tvalid(phase_axis_data_tvalid),
      .b_tready(phase_gain_b_tready),
      .p_tdata(phase_gained_axis_tdata),
      .p_tlast(phase_gained_axis_tlast),
      .p_tvalid(phase_gained_axis_tvalid),
      .p_tready(phase_gained_axis_tready));


  //now round and clip both
  (* mark_debug = "true" *) wire [15:0] mag_clipped_axis_tdata;
  (* mark_debug = "true" *) wire mag_clipped_axis_tlast, mag_clipped_axis_tvalid, mag_clipped_axis_tready;
  wire [15:0] phase_clipped_axis_tdata;
  wire phase_clipped_axis_tlast, phase_clipped_axis_tvalid, phase_clipped_axis_tready;

  axi_round_and_clip #(
      .WIDTH_IN(26),
      .WIDTH_OUT(16),
      .CLIP_BITS(2), //has nothing to do with scaling
      .FIFOSIZE(0)) mag_round (
   .clk(ce_clk),
   .reset(ce_rst),
   .i_tdata(mag_gained_axis_tdata),
   .i_tlast(mag_gained_axis_tlast),
   .i_tready(mag_gained_axis_tready),
   .i_tvalid(mag_gained_axis_tvalid),
   .o_tdata(mag_clipped_axis_tdata),
   .o_tlast(mag_clipped_axis_tlast),
   .o_tready(mag_clipped_axis_tready),
   .o_tvalid(mag_clipped_axis_tvalid));

  axi_round_and_clip #(
      .WIDTH_IN(26),
      .WIDTH_OUT(16),
      .CLIP_BITS(2), //has nothing to do with scaling
      .FIFOSIZE(0)) phase_round (
   .clk(ce_clk),
   .reset(ce_rst),
   .i_tdata(phase_gained_axis_tdata),
   .i_tlast(phase_gained_axis_tlast),
   .i_tready(phase_gained_axis_tready),
   .i_tvalid(phase_gained_axis_tvalid),
   .o_tdata(phase_clipped_axis_tdata),
   .o_tlast(phase_clipped_axis_tlast),
   .o_tready(phase_clipped_axis_tready),
   .o_tvalid(phase_clipped_axis_tvalid));

  //now join both into a single stream
  join_complex #(.WIDTH(16)) joiner(
     .ii_tdata(mag_clipped_axis_tdata),
     .ii_tlast(mag_clipped_axis_tlast),
     .ii_tready(mag_clipped_axis_tready),
     .ii_tvalid(mag_clipped_axis_tvalid),
     .iq_tdata(phase_clipped_axis_tdata),
     .iq_tlast(phase_clipped_axis_tlast),
     .iq_tready(phase_clipped_axis_tready),
     .iq_tvalid(phase_clipped_axis_tvalid),
     .o_tdata(s_axis_data_tdata),
     .o_tlast(s_axis_data_tlast),
     .o_tvalid(s_axis_data_tvalid),
     .o_tready(s_axis_data_tready));

endmodule
