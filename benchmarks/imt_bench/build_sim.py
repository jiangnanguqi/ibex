#!/usr/bin/env python3
"""Compile unchanged core/SoC RTL plus additive loading and measurement hooks."""
import argparse,json,os,subprocess
from pathlib import Path

def build(here,output,verilator,jobs,ibex_config):
    root=here.parents[1]
    core=json.loads((here/'core.json').read_text())['core']
    revision=json.loads((here/'core.json').read_text())['source_commit']
    paths=['rtl','vendor','shared'] if core=='ibex' else ['rtl','bhv','cv32e40p_manifest.flist']
    subprocess.run(['git','diff','--exit-code',revision,'--',*paths],cwd=root,
                   check=True,stdout=subprocess.DEVNULL)
    output.mkdir(parents=True,exist_ok=True)
    args=[verilator,'--cc','--exe','--build','-j',str(jobs),'-O3',
          '-Wno-fatal','--Mdir',str(output),'-o','Vbench','-CFLAGS','-O3',
          '--unroll-count','72','-MAKEFLAGS','OPT_FAST=-O3 OPT_SLOW=-O3']
    files=[]
    if core=='ibex':
        prim=root/'vendor/lowrisc_ip/ip/prim/rtl'
        generic=root/'vendor/lowrisc_ip/ip/prim_generic/rtl'
        # FuseSoC normally generates these generic primitive aliases. Generate
        # build-only copies with the module name changed, keeping logic intact.
        for name in ['buf','flop','clock_gating','ram_1p','ram_2p']:
            source=generic/f'prim_generic_{name}.sv'
            target=output/f'prim_{name}.sv'
            content=source.read_text().replace('module prim_generic_'+name,
                                               'module prim_'+name,1)
            if not target.exists() or target.read_text()!=content:target.write_text(content)
            files.append(target)
        packages=[prim/'prim_util_pkg.sv',prim/'prim_ram_1p_pkg.sv',prim/'prim_ram_2p_pkg.sv',prim/'prim_secded_pkg.sv',prim/'prim_cipher_pkg.sv',root/'rtl/ibex_pkg.sv',root/'rtl/ibex_tracer_pkg.sv']
        files=packages+files+[prim/'prim_lfsr.sv']
        files+=sorted(p for p in (root/'rtl').glob('*.sv') if not p.name.endswith('_pkg.sv'))
        files+=list((root/'shared/rtl').glob('*.sv'))+[root/'shared/rtl/sim/simulator_ctrl.sv',root/'examples/simple_system/rtl/ibex_simple_system.sv',here/'ibex_hooks.sv']
        args+=['--top-module','ibex_simple_system','-DRVFI','-CFLAGS','-DBENCH_IBEX',
               '-I'+str(prim),'-I'+str(root/'rtl'),
               '-I'+str(root/'vendor/lowrisc_ip/dv/sv/dv_utils')]
        if ibex_config=='maxperf':
            args+=['-DRV32M=ibex_pkg::RV32MSingleCycle','-GBranchTargetALU=1','-GWritebackStage=1']
        else:args+=['-DRV32M=ibex_pkg::RV32MFast','-GBranchTargetALU=0','-GWritebackStage=0']
        args+=['-GICache=0','-GRV32E=0','-GMHPMCounterNum=0','-DRV32B=ibex_pkg::RV32BNone']
    else:
        rtl=root/'rtl'
        for line in (root/'cv32e40p_manifest.flist').read_text().splitlines():
            if not line.startswith('${DESIGN_RTL_DIR}'):continue
            p=Path(line.replace('${DESIGN_RTL_DIR}',str(rtl))).resolve()
            if p.name in ['cv32e40p_tb_wrapper.sv','cv32e40p_tracer_pkg.sv']:continue
            files.append(p)
        # The upstream packed CSR arrays have continuous assignments for absent
        # counters and flop assignments for implemented counters (disjoint bits).
        # Verilator 5.020 otherwise diagnoses the entire packed array as mixed.
        args+=['--top-module','bench_top','-I'+str(rtl/'include'),'-Wno-BLKANDNBLK']
        files.append(here/'cv32e40p_top.sv')
    files += [here/'bench_audit.sv',here/'sim_main.cc']
    args+=list(map(str,files))
    (output/'command.json').write_text(json.dumps(args,indent=2)+'\n')
    # Verilator generates its makefile dependencies; repeat calls are incremental.
    with (output/'build.log').open('w') as log:
        result=subprocess.run(args,cwd=here,stdout=log,stderr=subprocess.STDOUT)
    if result.returncode:
        print((output/'build.log').read_text()[-12000:])
        raise RuntimeError('Verilator build failed; see '+str(output/'build.log'))
    return output/'Vbench'

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build-dir',type=Path,required=True)
    p.add_argument('--verilator',default='verilator')
    p.add_argument('--jobs',type=int,default=2)
    p.add_argument('--ibex-config',choices=['small','maxperf'],default='small')
    a=p.parse_args();build(Path(__file__).resolve().parent,a.build_dir.resolve(),a.verilator,a.jobs,a.ibex_config)
