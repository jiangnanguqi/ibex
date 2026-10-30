// SPDX-License-Identifier: Apache-2.0
// Standalone, no-cache, single-HART system with independent one-cycle I/D ports.
module bench_top(input logic clk_i,rst_ni);
 logic instr_req,instr_valid,data_req,data_valid,data_we;
 logic [31:0] instr_addr,instr_rdata,data_addr,data_wdata,data_rdata;
 logic [3:0] data_be;
 logic [31:0] mem[262144];
 string program_hex;
 integer log_fd;
 logic [2:0] finish_count;
 initial begin
  if(!$value$plusargs("memhex=%s",program_hex)) $fatal(1,"Missing +memhex");
  $readmemh(program_hex,mem);
  log_fd=$fopen("program.log","w");
  $display("BENCH_SIM_CONFIG core=cv32e40p harts=1 cache=0 corev_pulp=0 fpu=0 memory_bytes=1048576 memory_response_cycles=1");
 end
 final $fclose(log_fd);
 int debug_cycles;
 always @(posedge clk_i) begin
  debug_cycles<=debug_cycles+1;
  if($test$plusargs("bench_debug") && debug_cycles<200)
   $display("CV_DEBUG cycle=%0d rst=%b ireq=%b iaddr=%h irdata=%h dreq=%b dwe=%b daddr=%h dwdata=%h",debug_cycles,rst_ni,instr_req,instr_addr,instr_rdata,data_req,data_we,data_addr,data_wdata);
 end
 always @(posedge clk_i) begin
  if(!rst_ni) begin instr_valid<=0;data_valid<=0;finish_count<=0;end
  else begin
   instr_valid<=instr_req;
   data_valid<=data_req;
   if(instr_req) begin
    if(instr_addr<32'h100000 || instr_addr>=32'h200000) $fatal(1,"Instruction address out of RAM: %h",instr_addr);
    instr_rdata<=mem[instr_addr[19:2]];
   end
   if(data_req) begin
    if(data_addr>=32'h100000 && data_addr<32'h200000) begin
     data_rdata<=mem[data_addr[19:2]];
     if(data_we) for(int b=0;b<4;b++) if(data_be[b]) mem[data_addr[19:2]][8*b+:8]<=data_wdata[8*b+:8];
    end else if(data_addr==32'h20000) begin
     data_rdata<=0;
     if(data_we && data_be[0]) begin $fwrite(log_fd,"%c",data_wdata[7:0]);$fflush(log_fd);end
    end else if(data_addr==32'h20008) begin
     data_rdata<=0;
     if(data_we && data_wdata[0])finish_count<=1;
    end else $fatal(1,"Data address out of map: %h",data_addr);
   end
   if(finish_count!=0)finish_count<=finish_count+1;
   if(finish_count==3)$finish;
  end
 end
 cv32e40p_top #(.COREV_PULP(0),.COREV_CLUSTER(0),.FPU(0),.ZFINX(0),.NUM_MHPMCOUNTERS(0)) core (
  .clk_i,.rst_ni,.pulp_clock_en_i(1'b1),.scan_cg_en_i(1'b0),
  .boot_addr_i(32'h100080),.mtvec_addr_i(32'h100000),
  .dm_halt_addr_i(32'h100000),.dm_exception_addr_i(32'h100000),.hart_id_i(32'b0),
  .instr_req_o(instr_req),.instr_gnt_i(instr_req),.instr_rvalid_i(instr_valid),
  .instr_addr_o(instr_addr),.instr_rdata_i(instr_rdata),
  .data_req_o(data_req),.data_gnt_i(data_req),.data_rvalid_i(data_valid),
  .data_we_o(data_we),.data_be_o(data_be),.data_addr_o(data_addr),.data_wdata_o(data_wdata),.data_rdata_i(data_rdata),
  .irq_i(32'b0),.irq_ack_o(),.irq_id_o(),.debug_req_i(1'b0),
  .debug_havereset_o(),.debug_running_o(),.debug_halted_o(),.fetch_enable_i(1'b1),.core_sleep_o()
 );
 bench_audit audit(
  .clk_i,.rst_ni,.inhibit_i(core.core_i.cs_registers_i.mcountinhibit_q),
  .retired_i(core.core_i.cs_registers_i.hpm_events[1]),
  .output_write_i(data_req && data_we && data_be[0] && data_addr==32'h20000),
  .exit_write_i(data_req && data_we && data_addr==32'h20008 && data_wdata[0]),.exit_value_i(data_wdata)
 );
endmodule
