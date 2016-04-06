//
// Copyright 2011 Ettus Research LLC
//

module ram_2port_next
  #(parameter DWIDTH=32,
    parameter AWIDTH=9)
    (input clka,
     input ena,
     input wea,
     input [AWIDTH-1:0] addra,
     input [DWIDTH-1:0] dia,
     output reg [DWIDTH-1:0] doa,
     output reg [DWIDTH-1:0] doa_next,

     input clkb,
     input enb,
     input web,
     input [AWIDTH-1:0] addrb,
     input [DWIDTH-1:0] dib,
     output reg [DWIDTH-1:0] dob,
     output reg [DWIDTH-1:0] dob_next
  );

   reg [DWIDTH-1:0] ram [(1<<AWIDTH)-1:0];
   /*
   integer 	    i;
   initial
     for(i=0;i<(1<<AWIDTH);i=i+1)
       ram[i] <= {DWIDTH{1'b0}};
       */

   always @(posedge clka) begin
      if (ena)
        begin
           if (wea)
             ram[addra] <= dia;
           doa <= ram[addra];
           doa_next <= ram[addra+1];
        end
   end
   always @(posedge clkb) begin
      if (enb)
        begin
           if (web)
             ram[addrb] <= dib;
           dob <= ram[addrb];
           dob_next <= ram[addrb+1];
        end
   end
endmodule // ram_2port
