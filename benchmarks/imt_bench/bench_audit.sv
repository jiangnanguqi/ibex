// SPDX-License-Identifier: Apache-2.0
// Observe real core counter gates and accepted output transactions.
module bench_audit (
 input logic clk_i,rst_ni,
 input logic [31:0] inhibit_i,
 input logic retired_i, output_write_i, exit_write_i,
 input logic [31:0] exit_value_i
);
 bit armed,was_active,finished;
 longint unsigned cycles,instructions,output_writes;
 int unsigned windows;
 wire active=~inhibit_i[0];
 always @(posedge clk_i) begin
  if(!rst_ni) begin
   armed<=0;was_active<=0;finished<=0;cycles<=0;instructions<=0;output_writes<=0;windows<=0;
  end else begin
   if(inhibit_i[0] && inhibit_i[2]) armed<=1;
   if(armed && active) begin
    cycles<=cycles+1;
    if(!was_active) windows<=windows+1;
   end
   if(armed && !inhibit_i[2] && retired_i) instructions<=instructions+1;
   was_active<=armed && active;
   if(output_write_i) begin
    if(!inhibit_i[0] || !inhibit_i[2]) $fatal(1,"Output occurred with performance counters enabled");
    output_writes<=output_writes+1;
   end
   if(exit_write_i && !finished) begin
    if(!inhibit_i[0] || !inhibit_i[2]) $fatal(1,"Exit occurred with counters enabled");
    finished<=1;
    $display("BENCH_AUDIT windows=%0d cycles=%0d instructions=%0d output_writes=%0d output_during_measurement=0",windows,cycles,instructions,output_writes);
    $display("BENCH_SIM_EXIT exit=%0d",exit_value_i>>1);
   end
  end
 end
endmodule
