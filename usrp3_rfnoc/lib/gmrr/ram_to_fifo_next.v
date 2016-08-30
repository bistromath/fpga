//
// Copyright 2014 Ettus Research LLC
//

// Dual ported ram attached to a FIFO for readout
//   Most useful for storing coefficients for windows, filters, etc.
//   Config port is used for writing in order
//   i_* (address in) and o_* (data out) ports are for streams, and can read out in arbitrary order
//
//   This version for GMRR includes a split_stream_fifo to output as well the
//   next address in the RAM.

module ram_to_fifo_next
  #(parameter DWIDTH=32,
    parameter AWIDTH=10)
   (input clk, input reset, input clear,
    input [DWIDTH-1:0] config_tdata, input config_tlast, input config_tvalid, output config_tready,
    input [AWIDTH-1:0] i_tdata, input i_tlast, input i_tvalid, output i_tready,
    output [DWIDTH-1:0] o0_tdata, output o0_tlast, output o0_tvalid, input o0_tready,
    output [DWIDTH-1:0] o1_tdata, output o1_tlast, output o1_tvalid, input o1_tready);

   // Write side
   reg [AWIDTH-1:0] write_addr;

   wire [DWIDTH-1:0] ram_tdata;
   reg ram_tlast, ram_tvalid;
   wire ram_tready;

   wire [DWIDTH-1:0] ram_next_tdata;

   wire [DWIDTH*2-1:0] o0_tdata_wide, o1_tdata_wide;

   assign config_tready = 1'b1;

   always @(posedge clk)
     if(reset | clear)
       write_addr <= 0;
     else
       if(config_tvalid & config_tready)
       if(config_tlast)
         write_addr <= 0;
       else
         write_addr <= write_addr + 1;

   ram_2port_next #(.DWIDTH(DWIDTH), .AWIDTH(AWIDTH)) ram_2port
     (.clka(clk), .ena(1'b1), .wea(config_tvalid), .addra(write_addr), .dia(config_tdata), .doa(), // Write port
      .clkb(clk), .enb(i_tready & i_tvalid), .web(1'b0), .addrb(i_tdata), .dib({DWIDTH{1'b1}}), .dob(ram_tdata), .dob_next(ram_next_tdata) // Read port
   );

   // Handle read side AXI flags
   assign i_tready = ~ram_tvalid | ram_tready;

   always @(posedge clk)
     if(reset | clear)
       begin
         ram_tvalid <= 1'b0;
         ram_tlast <= 1'b0;
       end
     else
       begin
         ram_tvalid <= (i_tready & i_tvalid) | (ram_tvalid & ~ram_tready);
         if(i_tready & i_tvalid)
            ram_tlast <= i_tlast;
       end

   //now let's abuse split_stream_fifo to get two AXI streams out of it
   //this isn't the most efficient way to go about things but it shouldn't be
   //awful
   split_stream_fifo #(.WIDTH(DWIDTH*2), .ACTIVE_MASK(4'b0011)) split_stream (
      .clk(clk), .reset(reset), .clear(clear),
      .i_tdata({ram_next_tdata, ram_tdata}), .i_tlast(ram_tlast), .i_tvalid(ram_tvalid), .i_tready(ram_tready),
      .o0_tdata(o0_tdata_wide), .o0_tlast(o0_tlast), .o0_tvalid(o0_tvalid), .o0_tready(o0_tready),
      .o1_tdata(o1_tdata_wide), .o1_tlast(o1_tlast), .o1_tvalid(o1_tvalid), .o1_tready(o1_tready)
   );

   assign o0_tdata = o0_tdata_wide[DWIDTH-1:0];
   assign o1_tdata = o1_tdata_wide[DWIDTH*2-1:DWIDTH];

endmodule // ram_to_fifo_next
