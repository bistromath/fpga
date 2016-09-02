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

  //----------------------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------------------
  // Readback register address
  wire [7:0] rb_addr[1:0];
  reg [63:0] rb_data[1:0];

  // RFNoC Shell
  wire [31:0] set_data[0:1];
  wire [7:0]  set_addr[0:1];
  wire [1:0]  set_stb;

  wire [1:0] clear_tx_seqnum;

  wire [63:0] str_sink_tdata;
  wire str_sink_tlast, str_sink_tvalid, str_sink_tready;

  wire [63:0] str_src_tdata[0:1];
  wire [1:0] str_src_tlast, str_src_tvalid, str_src_tready;

//  wire [63:0] cmdout_tdata, ackin_tdata;
//  wire        cmdout_tlast, cmdout_tvalid, cmdout_tready, ackin_tlast, ackin_tvalid, ackin_tready;

  wire [15:0] src_sid[0:1];
  wire [15:0] next_dst_sid[0:1], resp_out_dst_sid[0:1];
  wire [15:0] resp_in_dst_sid;

  // AXI Wrapper
  // input (sink) data
  wire [31:0]  m_axis_data_tdata;
  wire [127:0] m_axis_data_tuser;
  wire m_axis_data_tlast, m_axis_data_tvalid, m_axis_data_tready;

  // output (source) data
  wire [31:0]  s_axis_data_tdata[0:1];
  wire [127:0] s_axis_data_tuser[0:1];
  wire [1:0] s_axis_data_tlast, s_axis_data_tvalid, s_axis_data_tready;

  wire [63:0]   cmdout_tdata, ackin_tdata;
  wire          cmdout_tlast, cmdout_tvalid, cmdout_tready, ackin_tlast, ackin_tvalid, ackin_tready;

  //----------------------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------------------

  //----------------------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------------------
  //Settings registers
  wire [15:0] mag_gain;

  setting_reg #(.my_addr(SR_MAG_GAIN), .width(16)) sr_mag_gain(
    .clk(ce_clk), .rst(ce_rst), .strobe(set_stb[0]), .addr(set_addr[0]), .in(set_data[0]), .out(mag_gain), .changed());

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE),
    .INPUT_PORTS(1),
    .OUTPUT_PORTS(2))
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
    .rb_stb(2'b1),
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
    // Stream Sink
    .str_sink_tdata(str_sink_tdata),
    .str_sink_tlast(str_sink_tlast),
    .str_sink_tvalid(str_sink_tvalid),
    .str_sink_tready(str_sink_tready),
    // Stream Sources
    .str_src_tdata({str_src_tdata[1], str_src_tdata[0]}),
    .str_src_tlast(str_src_tlast),
    .str_src_tvalid(str_src_tvalid),
    .str_src_tready(str_src_tready),
    .clear_tx_seqnum(clear_tx_seqnum),
    // Stream IDs
    .src_sid({src_sid[1], src_sid[0]}),
    .next_dst_sid({next_dst_sid[1], next_dst_sid[0]}),
    .resp_in_dst_sid(resp_in_dst_sid),
    .resp_out_dst_sid({resp_out_dst_sid[1], resp_out_dst_sid[0]}),
    .debug(debug));

  assign ackin_tready = 1'b1;

  // AXI Wrapper - Convert RFNoC Shell interface into AXI stream interface
  axi_wrapper #(
    .SIMPLE_MODE(0)
  )
  axi_wrapper0 (
    .clk(ce_clk),
    .reset(ce_rst),
    // RFNoC Shell
    .clear_tx_seqnum(clear_tx_seqnum[0]),
    .next_dst(next_dst_sid[0]),
    .set_stb(),
    .set_addr(),
    .set_data(),
    .i_tdata(str_sink_tdata),
    .i_tlast(str_sink_tlast),
    .i_tvalid(str_sink_tvalid),
    .i_tready(str_sink_tready),
    .o_tdata(str_src_tdata[0]),
    .o_tlast(str_src_tlast[0]),
    .o_tvalid(str_src_tvalid[0]),
    .o_tready(str_src_tready[0]),
    // Internal AXI streams
    .m_axis_data_tdata(m_axis_data_tdata),
    .m_axis_data_tuser(m_axis_data_tuser),
    .m_axis_data_tlast(m_axis_data_tlast),
    .m_axis_data_tvalid(m_axis_data_tvalid),
    .m_axis_data_tready(m_axis_data_tready),
    .s_axis_data_tdata(s_axis_data_tdata[0]),
    .s_axis_data_tlast(s_axis_data_tlast[0]),
    .s_axis_data_tvalid(s_axis_data_tvalid[0]),
    .s_axis_data_tready(s_axis_data_tready[0]),
    .s_axis_data_tuser(s_axis_data_tuser[0]),
    .m_axis_config_tdata(),
    .m_axis_config_tlast(),
    .m_axis_config_tvalid(),
    .m_axis_config_tready());

  axi_wrapper #(
    .SIMPLE_MODE(0)
  )
  axi_wrapper1 (
    .clk(ce_clk),
    .reset(ce_rst),
    // RFNoC Shell
    .clear_tx_seqnum(clear_tx_seqnum[1]),
    .next_dst(next_dst_sid[1]),
    .set_stb(),
    .set_addr(),
    .set_data(),
    .i_tdata(),
    .i_tlast(),
    .i_tvalid(),
    .i_tready(),
    .o_tdata(str_src_tdata[1]),
    .o_tlast(str_src_tlast[1]),
    .o_tvalid(str_src_tvalid[1]),
    .o_tready(str_src_tready[1]),
    // Internal AXI streams
    .m_axis_data_tdata(),
    .m_axis_data_tuser(),
    .m_axis_data_tlast(),
    .m_axis_data_tvalid(),
    .m_axis_data_tready(),
    .s_axis_data_tdata(s_axis_data_tdata[1]),
    .s_axis_data_tlast(s_axis_data_tlast[1]),
    .s_axis_data_tvalid(s_axis_data_tvalid[1]),
    .s_axis_data_tready(s_axis_data_tready[1]),
    .s_axis_data_tuser(s_axis_data_tuser[1]),
    .m_axis_config_tdata(),
    .m_axis_config_tlast(),
    .m_axis_config_tvalid(),
    .m_axis_config_tready());

   cvita_hdr_modify cvita_hdr_modify_inst0 (
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

   cvita_hdr_modify cvita_hdr_modify_inst1 (
      .header_in(m_axis_data_tuser),
      .header_out(s_axis_data_tuser[1]),
      .use_pkt_type(1'b0),  .pkt_type(),
      .use_has_time(1'b0),  .has_time(),
      .use_eob(1'b0),       .eob(),
      .use_seqnum(1'b0),    .seqnum(),
      .use_length(1'b0),    .length(),
      .use_src_sid(1'b1),   .src_sid(src_sid[1]),
      .use_dst_sid(1'b1),   .dst_sid(next_dst_sid[1]),
      .use_vita_time(1'b0), .vita_time());

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
  //we right-shift the input by a bit to prevent
  //full-scale inputs from overflowing the CORDIC
  //output -- it's fixed at 16 bits.


  //ok now we have to think about how to turn this into a
  //complex-to-mag-and-normalized-signal block.
  //
  //there's two approaches: divide the input signal by its
  //magnitude, or use a phase modulator (basically just a LUT)
  //to convert the phase into a magnitude-1 signal.
  //
  //the latter approach is probably more complicated to implement, but
  //easier to synthesize.
  //
  //just need a cosine table and a sine table.
  //output_i = cos(2*pi*phase)
  //output_q = sin(2*pi*phase)
  //
  //you know, there's a third option, which is to just use another CORDIC
  //to do the operation for us. maybe that makes the most sense. just fix
  //the polar mag input to 1 and let the CORDIC do the phase mod. we can
  //modify the complex_to_magphase CORDIC IP to do the reverse...
  //

  complex_to_magphase inst_complex_to_magphase (
     .aclk(ce_clk),
     .aresetn(~ce_rst),
     .s_axis_cartesian_tdata({m_axis_data_tdata[31], m_axis_data_tdata[31:17], m_axis_data_tdata[15], m_axis_data_tdata[15:1]}),
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
     .oi_tready(phase_axis_data_tready),
     .error());

  //and multiply the mag by its gain
  wire [25:0] mag_gained_axis_tdata;
  wire mag_gained_axis_tlast, mag_gained_axis_tvalid, mag_gained_axis_tready;

  wire mag_gain_a_tready, mag_gain_b_tready;
  assign magnitude_axis_data_tready = mag_gain_a_tready & mag_gain_b_tready;

  //drop_top_p increased to 12 to shift the output back left again
  mult #(.WIDTH_A(16), .WIDTH_B(16), .WIDTH_P(26), .DROP_TOP_P(12)) inst_mag_gain(
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

  //now round and clip both
  wire [15:0] mag_clipped_axis_tdata;
  wire mag_clipped_axis_tlast, mag_clipped_axis_tvalid, mag_clipped_axis_tready;

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

  //use CORDIC phase modulator to convert phase to normalized output
  //this is just a xilinx IP CORDIC operating in sin/cos mode.
  wire [31:0] normal_axis_data_tdata;
  wire normal_axis_data_tready, normal_axis_data_tvalid, normal_axis_data_tlast;
  phase_modulator phase_mod(
   .aclk(ce_clk),
   .aresetn(~ce_rst),
   .s_axis_phase_tdata(phase_axis_data_tdata),
   .s_axis_phase_tready(phase_axis_data_tready),
   .s_axis_phase_tvalid(phase_axis_data_tvalid),
   .s_axis_phase_tlast(phase_axis_data_tlast),
   .m_axis_dout_tdata(normal_axis_data_tdata),
   .m_axis_dout_tready(normal_axis_data_tready),
   .m_axis_dout_tvalid(normal_axis_data_tvalid),
   .m_axis_dout_tlast(normal_axis_data_tlast));

  //two output streams now; output 0 is the magnitude data
  //expressed as SC16 with the Q set to zero.
  assign s_axis_data_tdata[0] = {mag_clipped_axis_tdata, 16'b0};
  assign s_axis_data_tlast[0] = mag_clipped_axis_tlast;
  assign mag_clipped_axis_tready = s_axis_data_tready[0];
  assign s_axis_data_tvalid[0] = mag_clipped_axis_tvalid;

  //output 1 is the normalized signal
  //just a regular SC16 stream.
  assign s_axis_data_tdata[1] = normal_axis_data_tdata;
  assign s_axis_data_tlast[1] = normal_axis_data_tlast;
  assign normal_axis_data_tready = s_axis_data_tready[1];
  assign s_axis_data_tvalid[1] = normal_axis_data_tvalid;

endmodule
