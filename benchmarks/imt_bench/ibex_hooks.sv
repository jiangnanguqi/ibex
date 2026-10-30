// SPDX-License-Identifier: Apache-2.0
// Add loading and auditing to the existing Simple System without editing it.
module imt_bench_hooks;
 string program_hex;
 initial begin
  if(!$value$plusargs("memhex=%s",program_hex)) $fatal(1,"Missing +memhex");
  $readmemh(program_hex,$root.ibex_simple_system.u_ram.u_ram.mem);
  $display("BENCH_SIM_CONFIG core=ibex harts=1 cache=%0d rv32m=%0d branch_target_alu=%0d writeback_stage=%0d branch_predictor=%0d memory_bytes=1048576 memory_response_cycles=1",
   $root.ibex_simple_system.ICache,$root.ibex_simple_system.RV32M,
   $root.ibex_simple_system.BranchTargetALU,$root.ibex_simple_system.WritebackStage,
   $root.ibex_simple_system.BranchPredictor);
 end
 always @(posedge $root.ibex_simple_system.clk_sys) begin
  if($test$plusargs("bench_debug") && $root.ibex_simple_system.u_top.u_ibex_top.u_ibex_core.cs_registers_i.csr_access_i)
   $display("CSR_DEBUG addr=%h priv=%h illegal=%b priv_error=%b write_error=%b dbg_error=%b",
    $root.ibex_simple_system.u_top.u_ibex_top.u_ibex_core.cs_registers_i.csr_addr_i,
    $root.ibex_simple_system.u_top.u_ibex_top.u_ibex_core.cs_registers_i.priv_lvl_q,
    $root.ibex_simple_system.u_top.u_ibex_top.u_ibex_core.cs_registers_i.illegal_csr,
    $root.ibex_simple_system.u_top.u_ibex_top.u_ibex_core.cs_registers_i.illegal_csr_priv,
    $root.ibex_simple_system.u_top.u_ibex_top.u_ibex_core.cs_registers_i.illegal_csr_write,
    $root.ibex_simple_system.u_top.u_ibex_top.u_ibex_core.cs_registers_i.illegal_csr_dbg);
 end
 bench_audit audit (
  .clk_i($root.ibex_simple_system.clk_sys),.rst_ni($root.ibex_simple_system.rst_sys_n),
  .inhibit_i($root.ibex_simple_system.u_top.u_ibex_top.u_ibex_core.cs_registers_i.mcountinhibit),
  .retired_i($root.ibex_simple_system.u_top.u_ibex_top.u_ibex_core.cs_registers_i.instr_ret_i),
  .output_write_i($root.ibex_simple_system.host_req[0] && $root.ibex_simple_system.host_gnt[0] &&
    $root.ibex_simple_system.host_we[0] && $root.ibex_simple_system.host_addr[0]==32'h20000),
  .exit_write_i($root.ibex_simple_system.host_req[0] && $root.ibex_simple_system.host_gnt[0] &&
    $root.ibex_simple_system.host_we[0] && $root.ibex_simple_system.host_addr[0]==32'h20008 &&
    $root.ibex_simple_system.host_wdata[0][0]),
  .exit_value_i($root.ibex_simple_system.host_wdata[0])
 );
endmodule
bind ibex_simple_system imt_bench_hooks imt_hooks();
