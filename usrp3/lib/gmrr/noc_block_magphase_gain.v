//
// Copyright 2015 GMRR
//

module noc_block_magphase_gain #(
  parameter NOC_ID = 64'h8844_0000_0000_0000,
  parameter NOC_ID_2 = 64'h8844_0001_0000_0000,
  parameter STR_SINK_FIFOSIZE = 11)
(
  input bus_clk,
  input bus_rst,

  input ce_clk,
  input ce_rst,

  input [127:0] i_tdata,
  input [1:0] i_tlast,
  input [1:0] i_tvalid,
  output [1:0] i_tready,

  output [127:0] o_tdata,
  output [1:0] o_tlast,
  output [1:0] o_tvalid,
  input  [1:0] o_tready,

  output [63:0] debug);

  //----------------------------------------------------------------------------
  // Constants
  //----------------------------------------------------------------------------

  // Settings registers addresses
  localparam SR_MAG_GAIN      = 192;
  localparam SR_SQUELCH_LEVEL = 193;

  //----------------------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------------------
  // Readback register address
//  wire [7:0] rb_addr[0:1];
//  reg [63:0] rb_data[0:1];

  // RFNoC Shell
  wire [31:0] set_data[0:1];
  wire [7:0]  set_addr[0:1];
  wire [1:0]  set_stb;

  wire [1:0] clear_tx_seqnum;

  wire [63:0] str_sink_tdata[0:1];
  wire [1:0]  str_sink_tlast, str_sink_tvalid, str_sink_tready;

  wire [63:0] str_src_tdata[0:1];
  wire [1:0]  str_src_tlast, str_src_tvalid, str_src_tready;

  wire [15:0] src_sid[0:1];
  wire [15:0] next_dst_sid[0:1], resp_out_dst_sid[0:1];
  wire [15:0] resp_in_dst_sid[0:1];

  // AXI Wrapper
  // input (sink) data
  wire [31:0] m_axis_data_tdata;
  wire        m_axis_data_tlast, m_axis_data_tvalid, m_axis_data_tready;

  // output (source) data
  wire [31:0] s_axis_data_tdata[0:1];
  wire [1:0]  s_axis_data_tlast, s_axis_data_tvalid, s_axis_data_tready;

  wire [127:0] m_axis_data_tuser, s_axis_data_tuser_1;

  //----------------------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------------------

  //----------------------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------------------
  //Settings registers
  wire [15:0] mag_gain;
  wire [15:0] squelch_level;

  setting_reg #(.my_addr(SR_MAG_GAIN), .width(16)) sr_mag_gain(
    .clk(ce_clk), .rst(ce_rst), .strobe(set_stb[0]), .addr(set_addr[0]), .in(set_data[0]), .out(mag_gain), .changed());
  setting_reg #(.my_addr(SR_SQUELCH_LEVEL), .width(16)) sr_squelch_level(
    .clk(ce_clk), .rst(ce_rst), .strobe(set_stb[0]), .addr(set_addr[0]), .in(set_data[0]), .out(squelch_level), .changed());

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE),
    .INPUT_PORTS(1),
    .OUTPUT_PORTS(1))
  noc_shell (
    .bus_clk(bus_clk),
    .bus_rst(bus_rst),
    .i_tdata(i_tdata[63:0]),
    .i_tlast(i_tlast[0]),
    .i_tvalid(i_tvalid[0]),
    .i_tready(i_tready[0]),
    .o_tdata(o_tdata[63:0]),
    .o_tlast(o_tlast[0]),
    .o_tvalid(o_tvalid[0]),
    .o_tready(o_tready[0]),
    // Computer Engine Clock Domain
    .clk(ce_clk),
    .reset(ce_rst),
    // Control Sink
    .set_data(set_data[0]),
    .set_addr(set_addr[0]),
    .set_stb(set_stb[0]),
    .rb_data(),
    .rb_stb(1'b1),
    .rb_addr(),
    // Control Source (unused)
    .cmdout_tdata(),
    .cmdout_tlast(),
    .cmdout_tvalid(),
    .cmdout_tready(),
    .ackin_tdata(),
    .ackin_tlast(),
    .ackin_tvalid(),
    .ackin_tready(),
    // Stream Sink
    .str_sink_tdata(str_sink_tdata[0]),
    .str_sink_tlast(str_sink_tlast[0]),
    .str_sink_tvalid(str_sink_tvalid[0]),
    .str_sink_tready(str_sink_tready[0]),
    // Stream Sources
    .str_src_tdata(str_src_tdata[0]),
    .str_src_tlast(str_src_tlast[0]),
    .str_src_tvalid(str_src_tvalid[0]),
    .str_src_tready(str_src_tready[0]),
    .clear_tx_seqnum(clear_tx_seqnum[0]),
    // Stream IDs
    .src_sid(src_sid[0]),
    .next_dst_sid(next_dst_sid[0]),
    .resp_in_dst_sid(),
    .resp_out_dst_sid(),
    .debug(debug));

  noc_shell #(
    .NOC_ID(NOC_ID_2),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE),
    .INPUT_PORTS(1),
    .OUTPUT_PORTS(1))
  inst_noc_shell_1 (
    .bus_clk(bus_clk),
    .bus_rst(bus_rst),
    .i_tdata(i_tdata[127:64]),
    .i_tlast(i_tlast[1]),
    .i_tvalid(i_tvalid[1]),
    .i_tready(i_tready[1]),
    .o_tdata(o_tdata[127:64]),
    .o_tlast(o_tlast[1]),
    .o_tvalid(o_tvalid[1]),
    .o_tready(o_tready[1]),
    // Computer Engine Clock Domain
    .clk(ce_clk),
    .reset(ce_rst),
    // Control Sink
    .set_data(),
    .set_addr(),
    .set_stb(),
    .rb_data(),
    .rb_stb(1'b1),
    .rb_addr(),
    // Control Source (unused)
    .cmdout_tdata(),
    .cmdout_tlast(),
    .cmdout_tvalid(),
    .cmdout_tready(),
    .ackin_tdata(),
    .ackin_tlast(),
    .ackin_tvalid(),
    .ackin_tready(),
    // Stream Sink
    .str_sink_tdata(),
    .str_sink_tlast(),
    .str_sink_tvalid(),
    .str_sink_tready(),
    // Stream Sources
    .str_src_tdata(str_src_tdata[1]),
    .str_src_tlast(str_src_tlast[1]),
    .str_src_tvalid(str_src_tvalid[1]),
    .str_src_tready(str_src_tready[1]),
    .clear_tx_seqnum(clear_tx_seqnum[1]),
    // Stream IDs
    .src_sid(src_sid[1]),
    .next_dst_sid(next_dst_sid[1]),
    .resp_in_dst_sid(),
    .resp_out_dst_sid(),
    .debug());

  assign ackin_tready = 1'b1;

  axi_wrapper #(.MTU(10), .SIMPLE_MODE(1)) inst_axi_wrapper_0(
    .clk(ce_clk), .reset(ce_rst), .clear_tx_seqnum(clear_tx_seqnum[0]),
    .next_dst(next_dst_sid[0]),
    .set_stb(set_stb[0]), .set_addr(set_addr[0]), .set_data(set_data[0]),
    .i_tdata(str_sink_tdata[0]), .i_tlast(str_sink_tlast[0]), .i_tvalid(str_sink_tvalid[0]), .i_tready(str_sink_tready[0]),
    .o_tdata(str_src_tdata[0]), .o_tlast(str_src_tlast[0]), .o_tvalid(str_src_tvalid[0]), .o_tready(str_src_tready[0]),
    .m_axis_data_tdata(m_axis_data_tdata), .m_axis_data_tlast(m_axis_data_tlast), .m_axis_data_tvalid(m_axis_data_tvalid), .m_axis_data_tready(m_axis_data_tready), .m_axis_data_tuser(m_axis_data_tuser),
    .s_axis_data_tdata(s_axis_data_tdata[0]), .s_axis_data_tlast(s_axis_data_tlast[0]), .s_axis_data_tvalid(s_axis_data_tvalid[0]), .s_axis_data_tready(s_axis_data_tready[0]));

  axi_wrapper #(.MTU(10), .SIMPLE_MODE(0)) inst_axi_wrapper_1(
    .clk(ce_clk), .reset(ce_rst), .clear_tx_seqnum(clear_tx_seqnum[1]),
    .next_dst(next_dst_sid[1]),
    .set_stb(), .set_addr(), .set_data(),
    .i_tdata(), .i_tlast(), .i_tvalid(), .i_tready(),
    .o_tdata(str_src_tdata[1]), .o_tlast(str_src_tlast[1]), .o_tvalid(str_src_tvalid[1]), .o_tready(str_src_tready[1]),
    .m_axis_data_tdata(), .m_axis_data_tlast(), .m_axis_data_tvalid(), .m_axis_data_tready(1'b1),
    .s_axis_data_tdata(s_axis_data_tdata[1]), .s_axis_data_tlast(s_axis_data_tlast[1]), .s_axis_data_tvalid(s_axis_data_tvalid[1]), .s_axis_data_tready(s_axis_data_tready[1]), .s_axis_data_tuser(s_axis_data_tuser_1_reg));

  //i uh think this works?
  reg sof_in = 1'b1;
  reg [127:0] m_axis_data_tuser_reg;
  always @(posedge ce_clk) begin
    if(ce_rst | clear_tx_seqnum[0])
      sof_in <= 1'b1;
    if(m_axis_data_tvalid & m_axis_data_tready)
      if(m_axis_data_tlast)
        sof_in <= 1'b1;
      else
        sof_in <= 1'b0;
    if(sof_in & m_axis_data_tvalid & m_axis_data_tready)
      m_axis_data_tuser_reg <= m_axis_data_tuser;
  end

  cvita_hdr_modify cvita_hdr_modify_inst(
    .header_in(m_axis_data_tuser_reg),
    .header_out(s_axis_data_tuser_1),
    .use_pkt_type(1'b0), .pkt_type(),
    .use_has_time(1'b0), .has_time(),
    .use_eob(1'b0), .eob(),
    .use_seqnum(1'b0), .seqnum(),
    .use_length(1'b0), .length(),
    .use_payload_length(1'b0), .payload_length(),
    .use_src_sid(1'b1), .src_sid(src_sid[1]),
    .use_dst_sid(1'b1), .dst_sid(next_dst_sid[1]),
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

  //this bullshit in cart_tdata is sign extension

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

  wire [31:0] phase_split_tdata;
  split_stream_fifo #(.WIDTH(32), .ACTIVE_MASK(4'b0011)) inst_split_complex (
      .clk(ce_clk),
      .reset(ce_rst),
      .clear(1'b0),
      .i_tdata(magphase_axis_data_tdata),
      .i_tlast(magphase_axis_data_tlast),
      .i_tvalid(magphase_axis_data_tvalid),
      .i_tready(magphase_axis_data_tready),
      .o0_tdata(magnitude_axis_data_tdata),
      .o0_tlast(magnitude_axis_data_tlast),
      .o0_tvalid(magnitude_axis_data_tvalid),
      .o0_tready(magnitude_axis_data_tready),
      .o1_tdata(phase_split_tdata),
      .o1_tlast(phase_axis_data_tlast),
      .o1_tvalid(phase_axis_data_tvalid),
      .o1_tready(phase_axis_data_tready),
      .o2_tready(1'b1),
      .o3_tready(1'b1));

  assign phase_axis_data_tdata = phase_split_tdata[31:16];

  //so we split the output into two 16bit streams
/*  split_complex #(.WIDTH(16)) inst_split_complex (
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
*/
  //and multiply the mag by its gain
  wire [25:0] mag_gained_axis_tdata;
  wire mag_gained_axis_tlast, mag_gained_axis_tvalid, mag_gained_axis_tready;

  wire mag_gain_a_tready, mag_gain_b_tready;
  assign magnitude_axis_data_tready = mag_gain_a_tready & mag_gain_b_tready;

  wire [15:0] mag_squelched_axis_tdata;
  assign mag_squelched_axis_tdata = (magnitude_axis_data_tdata > squelch_level) ? magnitude_axis_data_tdata : 0;

  //drop_top_p increased to 12 to shift the output back left again
  mult #(.WIDTH_A(16), .WIDTH_B(16), .WIDTH_P(26), .DROP_TOP_P(12)) inst_mag_gain(
      .clk(ce_clk),
      .reset(ce_rst),
      .a_tdata(mag_squelched_axis_tdata),
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
