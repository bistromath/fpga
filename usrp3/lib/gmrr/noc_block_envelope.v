//
// Copyright 2015 GMRR
//

module noc_block_envelope #(
  parameter NOC_ID = 64'hB010_0000_0000_0000,
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
  wire [15:0] next_dst[0:1];

  // Readback register address
  wire rb_addr;

  //Settings registers

  // RFNoC Shell
  wire [31:0] set_data;
  wire [7:0]  set_addr;
  wire        set_stb;

  wire clear_tx_seqnum;

  wire [63:0] str_sink_tdata;
  wire str_sink_tlast, str_sink_tvalid, str_sink_tready;

  wire [127:0] str_src_tdata;
  wire [1:0] str_src_tlast, str_src_tvalid, str_src_tready;

  // AXI Wrapper
  // input (sink) data
  wire [31:0]  m_axis_data_tdata;
  wire [127:0] m_axis_data_tuser;
  wire m_axis_data_tlast, m_axis_data_tvalid, m_axis_data_tready;

  // output (source) data
  wire [31:0]  s_axis_data_tdata;
  wire [127:0] s_axis_data_tuser;
  wire s_axis_data_tlast, s_axis_data_tvalid, s_axis_data_tready;

  //CHDR headers, post- and pre-munged (for multiple output SIDs)
  wire [127:0]  out_tuser[0:1], out_tuser_pre[0:1];
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
  sr_next_dst0(.clk(ce_clk), .rst(ce_rst), .strobe(set_stb), .addr(set_addr), .in(set_data), .out(next_dst[0]), .changed());
  setting_reg #(.my_addr(SR_NEXT_DST+1), .width(16))
  sr_next_dst1(.clk(ce_clk), .rst(ce_rst), .strobe(set_stb), .addr(set_addr), .in(set_data), .out(next_dst[1]), .changed());


  // Readback registers
  setting_reg #(.my_addr(SR_READBACK), .width(1))
  sr_rdback (.clk(ce_clk), .rst(ce_rst), .strobe(set_stb), .addr(set_addr), .in(set_data), .out(rb_addr), .changed());

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE),
    .INPUT_PORTS(1),
    .OUTPUT_PORTS(2))
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


  chdr_deframer deframer (
      .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
      .i_tdata(str_sink_tdata), .i_tlast(str_sink_tlast), .i_tvalid(str_sink_tvalid), .i_tready(str_sink_tready),
      .o_tdata(m_axis_data_tdata), .o_tuser(m_axis_data_tuser), .o_tlast(m_axis_data_tlast), .o_tvalid(m_axis_data_tvalid), .o_tready(m_axis_data_tready));


  wire [31:0] magphase_axis_data_tdata;
  wire magphase_axis_data_tdata;
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
     .oi_tdata(magnitude_axis_data_tdata),
     .oi_tlast(magnitude_axis_data_tlast),
     .oi_tvalid(magnitude_axis_data_tvalid),
     .oi_tready(magnitude_axis_data_tready),
     .oq_tdata(phase_axis_data_tdata),
     .oq_tlast(phase_axis_data_tlast),
     .oq_tvalid(phase_axis_data_tvalid),
     .oq_tready(phase_axis_data_tready));


  //pack them back into SC16 output streams.
  //TODO this is only necessary if it's easier to cope with SC16 data
  //than to alter the output lengths so the output is S16
  //if you're going to pack things, you'll have to register the data somehow
  //TODO do you need a round-and-clip here?
  //OH, I see, the magnitude is 16 bit unsigned. we want 16 bit signed...
  //so yes, we round and clip that last bit.

  wire [31:0] mag_out_tdata;
  assign mag_out_tdata = {1'b0, magnitude_axis_data_tdata[15:0], 15'b0};

  wire [31:0] sc16_magnitude_axis_data_tdata;
  wire [31:0] sc16_phase_axis_data_tdata;

  wire mag_round_data_tlast, mag_round_data_tvalid, mag_round_data_tready;

  axi_round_and_clip #(.WIDTH_IN(32), .WIDTH_OUT(16), .CLIP_BITS(1))
    round_and_clip (
       .clk(ce_clk),
       .reset(ce_rst),
       .i_tdata(mag_out_tdata),
       .i_tlast(magnitude_axis_data_tlast),
       .i_tvalid(magnitude_axis_data_tvalid),
       .i_tready(magnitude_axis_data_tready),
       .o_tdata(sc16_magnitude_axis_data_tdata[31:16]),
       .o_tlast(mag_round_data_tlast),
       .o_tvalid(mag_round_data_tvalid),
       .o_tready(mag_round_data_tready));

  assign sc16_magnitude_axis_data_tdata[15:0] = {16'b0};
  assign sc16_phase_axis_data_tdata = {phase_axis_data_tdata, 16'b0};

  //we split the tuser fifo into two outputs to buffer the CHDR data
  split_stream_fifo #(
    .WIDTH(128), .ACTIVE_MASK(4'b0011))
  tuser_splitter (
    .clk(ce_clk), .reset(ce_rst), .clear(1'b0),
    .i_tdata(m_axis_data_tuser), .i_tlast(1'b0), .i_tvalid(m_axis_data_tvalid & m_axis_data_tlast), .i_tready(),
    .o0_tdata(out_tuser_pre[0]), .o0_tlast(), .o0_tvalid(), .o0_tready(mag_round_data_tlast & mag_round_data_tready),
    .o1_tdata(out_tuser_pre[1]), .o1_tlast(), .o1_tvalid(), .o1_tready(phase_axis_data_tlast & phase_axis_data_tready),
    .o2_tready(1'b1), .o3_tready(1'b1));

  //...and munge the SRC SID so that it comes from two block ports
  //TODO alter length, if you're going to pack things
  assign out_tuser[0] = { out_tuser_pre[0][127:96], out_tuser_pre[0][79:68], 4'b0000, next_destination[0], out_tuser_pre[0][63:0] };
  assign out_tuser[1] = { out_tuser_pre[1][127:96], out_tuser_pre[1][79:68], 4'b0001, next_destination[1], out_tuser_pre[1][63:0] };

  chdr_framer #(
      .SIZE(10))
    magnitude_framer (
      .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum),
      .i_tdata(sc16_magnitude_axis_data_tdata),
      .i_tuser(out_tuser[0]),
      .i_tlast(mag_round_data_tlast),
      .i_tvalid(mag_round_data_tvalid),
      .i_tready(mag_round_data_tready),
      .o_tdata(str_src_tdata[63:0]),
      .o_tlast(str_src_tlast[0]),
      .o_tvalid(str_src_tvalid[0]),
      .o_tready(str_src_tready[0]));

   chdr_framer #(
      .SIZE(10))
    phase_framer (
      .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum),
      .i_tdata(sc16_phase_axis_data_tdata),
      .i_tuser(out_tuser[1]),
      .i_tlast(phase_axis_data_tlast),
      .i_tvalid(phase_axis_data_tvalid),
      .i_tready(phase_axis_data_tready),
      .o_tdata(str_src_tdata[127:64]),
      .o_tlast(str_src_tlast[1]),
      .o_tvalid(str_src_tvalid[1]),
      .o_tready(str_src_tready[1]));
  //----------------------------------------------------------------------------
  // Combinational Logic
  //----------------------------------------------------------------------------


  // Readback register values
  always @*
    case(rb_addr)
      default : rb_data <= 64'hBEEEEEEEEEEEEEEF;
    endcase

endmodule
