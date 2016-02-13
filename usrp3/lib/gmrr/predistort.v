//a predistorter is basically just a ram_to_fifo block.
//taps are loaded in serially to each predistorter,
//and the i_t* input is the (N-bit truncated) input sample data.
//The o_t* output is the lookup table output.
//The lookup table output has to be linearly
//interpolated using the truncated bits of the input
//data.
//
//now you have t[i] and t[i+1], and you need to interpolate.
//
//to do this, you first calculate d_t = t[i+1] - t[i].
//
//then get the remainder (truncated bits of the input). NOT ROUNDED.
//
//like this:
//
//
//  i  --------  [ ram 2port ]  --t[i]-fxf----------------------- [     ]
//               [           ]          f                         [ add ]
//               [           ]          \-- [ sub ] -- [      ] - [     ]
//               [    next   ]  --t[i+1]-f- [     ]    [ mult ]
//                                                     [      ]
//  r ------------------------------------------------ [      ]
//
//  WIDTH == input width, output width
//  DEPTH == entries in the table
//
//  i_t* == address data input (i)
//  o_t* == output data (t[i])
//  taps_t* == taps stream

module predistort
  #(parameter WIDTH=16, parameter DEPTH=7, parameter DROPBITS=10)
   (input clk, input reset, input clear,
    input [WIDTH-1:0] i_tdata, input i_tlast, input i_tvalid, output i_tready,
    output [WIDTH-1:0] o_tdata, output o_tlast, output o_tvalid, input o_tready,
    input [WIDTH-1:0] taps_tdata, input taps_tlast, input taps_tvalid, output taps_tready);


  wire [WIDTH-1:0] index_tdata;
  wire index_tlast, index_tvalid, index_tready;

  wire [WIDTH-1:0] remainder_tdata;
  wire remainder_tlast, remainder_tvalid, remainder_tready;

  wire [WIDTH-1:0] lut_tdata;
  wire lut_tlast, lut_tvalid, lut_tready;

  wire [WIDTH-1:0] lut_next_tdata;
  wire lut_next_tlast, lut_next_tvalid, lut_next_tready;

  wire [WIDTH-1:0] lut_stream0_tdata;
  wire lut_stream0_tlast, lut_stream0_tvalid, lut_stream0_tready;

  wire [WIDTH-1:0] lut_stream1_tdata;
  wire lut_stream1_tlast, lut_stream1_tvalid, lut_stream1_tready;

  wire [WIDTH-1:0] dt_tdata;
  wire dt_tlast, dt_tvalid, dt_tready;

  wire [WIDTH+DROPBITS-1:0] interp_tdata;
  wire interp_tlast, interp_tvalid, interp_tready;

  wire [WIDTH-1:0] interp_clip_tdata;
  wire interp_clip_tlast, interp_clip_tvalid, interp_clip_tready;

  //split the input stream into two separate AXI streams -- we'll extract the
  //index from one, the remainder from the other.
  split_stream_fifo #(.WIDTH(WIDTH), .ACTIVE_MASK(4'b0011)) input_splitter (
    .clk(clk), .reset(reset), .clear(clear),
    .i_tdata(i_tdata), .i_tlast(i_tlast), .i_tvalid(i_tvalid), .i_tready(i_tready),
    .o0_tdata(index_tdata), .o0_tlast(index_tlast), .o0_tvalid(index_tvalid), .o0_tready(index_tready),
    .o1_tdata(remainder_tdata), .o1_tlast(remainder_tlast), .o1_tvalid(remainder_tvalid), .o1_tready(remainder_tready)
 );

 //quantize incoming data to an index in the LUT and a remainder.
  wire [DEPTH-1:0] index_tdata_clip;
  wire [WIDTH-DEPTH-1:0] remainder_tdata_clip;
  assign index_tdata_clip = index_tdata[WIDTH-1:WIDTH-DEPTH];
  assign remainder_tdata_clip = remainder_tdata[WIDTH-DEPTH-1:0];

  //let's just isolate the LUT in its own file
  ram_to_fifo_next #(.DWIDTH(WIDTH), .AWIDTH(DEPTH)) lut (
     .clk(clk), .reset(reset), .clear(clear),
     .config_tdata(taps_tdata), .config_tlast(taps_tlast), .config_tvalid(taps_tvalid), .config_tready(taps_tready),
     .i_tdata(index_tdata_clip), .i_tlast(index_tlast), .i_tvalid(index_tvalid), .i_tready(index_tready),
     .o0_tdata(lut_tdata), .o0_tlast(lut_tlast), .o0_tvalid(lut_tvalid), .o0_tready(lut_tready),
     .o1_tdata(lut_next_tdata), .o1_tlast(lut_next_tlast), .o1_tvalid(lut_next_tvalid), .o1_tready(lut_next_tready)
  );

   //now we're buffered and can split the stream with a split_stream_fifo for
   //use with the sub block and the final mult block (see diagram above)
   split_stream_fifo #(.WIDTH(WIDTH), .ACTIVE_MASK(4'b0011)) lut_splitter (
      .clk(clk), .reset(reset), .clear(clear),
      .i_tdata(lut_tdata), .i_tlast(lut_tlast), .i_tvalid(lut_tvalid), .i_tready(lut_tready),
      .o0_tdata(lut_stream0_tdata), .o0_tlast(lut_stream0_tlast), .o0_tvalid(lut_stream0_tvalid), .o0_tready(lut_stream0_tready),
      .o1_tdata(lut_stream1_tdata), .o1_tlast(lut_stream1_tlast), .o1_tvalid(lut_stream1_tvalid), .o1_tready(lut_stream1_tready)
   );

   //now we're free to use lut and lut_next with our downstream blocks without
   //fear of things getting blocked up. no more constipation!
   //dude you don't need an "addsub" block for adding and subtracting in verilog
   //you can just add or subtract things... assuming you synchronize the AXI streams first.
   //the addsub block is designed for complex ints anyhow
   assign dt_tdata = lut_next_tdata - lut_stream0_tdata;
   assign dt_tlast = lut_next_tlast; //follow first input...
   assign dt_tvalid = lut_next_tvalid & lut_stream0_tvalid;
   assign lut_next_tready = dt_tvalid & dt_tready;
   assign lut_stream0_tready = dt_tvalid & dt_tready;

  //then there's a multiplier to mult the remainder by the difference
  mult #(.WIDTH_A(WIDTH), .WIDTH_B(WIDTH), .WIDTH_P(WIDTH+DROPBITS), .DROP_TOP_P(DROPBITS), .LATENCY(4)) mult_inst (
     .clk(clk), .reset(reset),
     .a_tdata({7'b0,remainder_tdata_clip}),
     .a_tlast(remainder_tlast),
     .a_tvalid(remainder_tvalid),
     .a_tready(remainder_tready),
     .b_tdata(dt_tdata),
     .b_tlast(dt_tlast),
     .b_tvalid(dt_tvalid),
     .b_tready(dt_tready),
     .p_tdata(interp_tdata),
     .p_tlast(interp_tlast),
     .p_tvalid(interp_tvalid),
     .p_tready(interp_tready)
  );

  //round off the multiplier output
  axi_round_and_clip #(
      .WIDTH_IN(WIDTH+DROPBITS),
      .WIDTH_OUT(WIDTH),
      .CLIP_BITS(2), //has nothing to do with scaling
      .FIFOSIZE(1)) corr_clip (
   .clk(clk),
   .reset(reset),
   .i_tdata(interp_tdata),
   .i_tlast(interp_tlast),
   .i_tready(interp_tready),
   .i_tvalid(interp_tvalid),
   .o_tdata(interp_clip_tdata),
   .o_tlast(interp_clip_tlast),
   .o_tready(interp_clip_tready),
   .o_tvalid(interp_clip_tvalid)
  );

  //and finally an adder to sum the correction with the stream1.
  //let's fix this...
   assign o_tdata = lut_stream1_tdata + interp_clip_tdata;
   assign o_tlast = lut_stream1_tlast; //follow first input...
   assign o_tvalid = lut_stream1_tvalid & interp_clip_tvalid;
   assign lut_stream1_tready = o_tvalid & o_tready;
   assign interp_clip_tready = o_tvalid & o_tready;

endmodule
