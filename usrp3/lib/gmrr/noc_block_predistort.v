//
// Copyright 2015 GMRR
//

module noc_block_predistort #(
  parameter NOC_ID = 64'h8855_0000_0000_0000,
  parameter STR_SINK_FIFOSIZE = 11,
  parameter NUM_CHANNELS = 4)
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
  //
  //just some notes for nick: JP said radio-redo now has separate register banks
  //for each input stream.
  //
  //the predistorter block might be better done as a separate block for each
  //one (there are four in total) but there are concerns with how many blocks
  //you can instantiate in RFNoC -- you might already be running up against the
  //xbar limit (11). so let's do the original thing and use four channels on a single
  //block, which instantiates a 'predistorter' object four times.

  // Settings registers addresses
  localparam SR_NEXT_DST    = 128;
  localparam SR_AXI_CONFIG  = 129;
  //parameter for setting which channel you're trying to load taps for.
  //this is not the best idea but i don't know how else to do it.
  localparam SR_WHICH_TAPS  = 192;
  localparam SR_READBACK    = 255;


  //----------------------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------------------

  // Set next destination in chain
  wire [15:0] next_dst[0:NUM_CHANNELS-1];

  // Readback register address
  // Make this wide enough to handle all your readback regs
  wire [1:0] rb_addr;

  // RFNoC Shell
  wire [31:0]             set_data;
  wire [7:0]              set_addr;
  wire [NUM_CHANNELS-1:0] set_stb;

  wire [63:0]   cmdout_tdata, ackin_tdata;
  wire          cmdout_tlast, cmdout_tvalid, cmdout_tready, ackin_tlast, ackin_tvalid, ackin_tready;

  wire [NUM_CHANNELS-1:0] clear_tx_seqnum;
  wire [15:0] src_sid[0:NUM_CHANNELS-1], next_dst_sid[0:NUM_CHANNELS-1];

  wire [63:0] str_sink_tdata[0:NUM_CHANNELS-1];
  wire [NUM_CHANNELS-1:0] str_sink_tlast, str_sink_tvalid, str_sink_tready;

  wire [63:0] str_src_tdata;
  wire str_src_tlast, str_src_tvalid, str_src_tready;

  // AXI Wrapper
  // input (sink) data
  wire [31:0]  in_tdata;
  wire [127:0] in_tuser;
  wire in_tlast, in_tvalid, in_tready;

  // output (source) data
  // remember, our data is four streams of real numbers (magnitudes).
  // to keep things simple, we use sc16 type with Q=0 for float data.
  wire [31:0]  out_tdata[0:NUM_CHANNELS-1]; //this syntax is fucked.
  wire [127:0] out_tuser[0:NUM_CHANNELS-1]; //remember to hand dupe this
  wire [127:0] out_tuser_pre[0:NUM_CHANNELS-1]; //remember to hand dupe this
  wire [NUM_CHANNELS-1:0] out_tlast, out_tvalid, out_tready;

  //----------------------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------------------

  // Readback register data
  reg [63:0] rb_data;

  //----------------------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------------------

  //Settings registers


  // Readback registers
  setting_reg #(.my_addr(SR_READBACK), .width(2))
  sr_rdback (.clk(ce_clk), .rst(ce_rst), .strobe(set_stb), .addr(set_addr), .in(set_data), .out(rb_addr), .changed());

  // RFNoC Shell
  noc_shell #(
    .NOC_ID(NOC_ID),
    .STR_SINK_FIFOSIZE(STR_SINK_FIFOSIZE),
    .INPUT_PORTS(1),
    .OUTPUT_PORTS(NUM_CHANNELS))
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
    // Stream Sources //TODO should be parameterized for NUM_CHANNELS
    .str_src_tdata({str_src_tdata[3], str_src_tdata[2], str_src_tdata[1], str_src_tdata[0]}),
    .str_src_tlast({str_src_tlast[3], str_src_tlast[2], str_src_tlast[1], str_src_tlast[0]}),
    .str_src_tvalid({str_src_tvalid[3], str_src_tvalid[2], str_src_tvalid[1], str_src_tvalid[0]}),
    .str_src_tready({str_src_tready[3], str_src_tready[2], str_src_tready[1], str_src_tready[0]}),
    .clear_tx_seqnum(clear_tx_seqnum),
    .debug(debug));

  // AXI Wrapper - Convert RFNoC Shell interface into AXI stream interface
  //
  // FIXME: NF you're going to have to use chdr_deframer, unless recent
  // work to rfnoc-devel allows use of multiple streams in axi_wrapper, which
  // it doesn't.
   chdr_deframer deframer
     (.clk(ce_clk), .reset(ce_rst), .clear(1'b0),
      .i_tdata(str_sink_tdata), .i_tlast(str_sink_tlast), .i_tvalid(str_sink_tvalid), .i_tready(str_sink_tready),
      .o_tdata(in_tdata), .o_tuser(in_tuser), .o_tlast(in_tlast), .o_tvalid(in_tvalid), .o_tready(in_tready));

  genvar k;
  generate
    for(k = 0; k < NUM_CHANNELS; k = k + 1) begin


       //instantiate a settings bus entry for destination
       setting_reg #(.my_addr(SR_NEXT_DST+k), .width(16)) new_destination
         (.clk(ce_clk), .rst(ce_rst), .strobe(set_stb), .addr(set_addr), .in(set_data),
         .out(next_dst[k]));
       //fix up the user stream TODO FIXME that 4'b0000 has to be equal to k
       assign out_tuser[k] = { out_tuser_pre[k][127:96], out_tuser_pre[k][79:68], 4'b0000, next_dst_sid[k], out_tuser_pre[k][63:0] };
       //put together a CHDR framer for the output
       chdr_framer #(.SIZE(10)) chdr_framer (
          .clk(ce_clk), .reset(ce_rst), .clear(clear_tx_seqnum[k]),
          .i_tdata(out_tdata[k]), .i_tuser(out_tuser[k]), .i_tlast(out_tlast[k]), .i_tvalid(out_tvalid[k]), .i_tready(out_tready[k]),
          .o_tdata(str_src_tdata[k*64+63:k*64]), .o_tlast(str_src_tlast[k]), .o_tvalid(str_src_tvalid[k]), .o_tready(str_src_tready[k]));
    end
  endgenerate


  // Readback register values
  // TODO load these up
  always @*
    case(rb_addr)
      2'd00    : rb_data <= mag_gain;
      default : rb_data <= 64'hBEEEEEEEEEEEEEEF;
    endcase

endmodule
