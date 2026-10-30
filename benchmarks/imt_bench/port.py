#!/usr/bin/env python3
"""Single-HART Embench and MLPerf Tiny flow, with unchanged upstream sources."""
import argparse,concurrent.futures,hashlib,json,os,re,struct,subprocess,sys,time
from pathlib import Path
import build_sim

HERE=Path(__file__).resolve().parent
CORE=json.loads((HERE/'core.json').read_text())
EMBENCH_COMMIT='09c2ed8c3b7008c95d08b038de4a3f6dc103ed70'
RV=['-march=rv32im','-mabi=ilp32','-misa-spec=2.2','-mcmodel=medany','-mstrict-align']

def write(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists() or path.read_text()!=text:path.write_text(text)

def command(args,**kwargs):
    subprocess.run(list(map(str,args)),check=True,cwd=HERE,**kwargs)

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def repository(path,url,commit):
    if not path.exists():
        path.parent.mkdir(parents=True,exist_ok=True)
        command(['git','init','-q',path])
        command(['git','-C',path,'remote','add','origin',url])
        command(['git','-C',path,'fetch','--depth=1','origin',commit])
        command(['git','-C',path,'checkout','--detach','FETCH_HEAD'])
    actual=subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
    if actual!=commit:raise RuntimeError(f'{path}: expected {commit}, found {actual}; not changed')
    command(['git','-C',path,'diff','--exit-code','HEAD','--'],stdout=subprocess.DEVNULL)

def prepare(a):
    if a.workload!='tiny':repository(a.embench_dir,'https://github.com/embench/embench-iot.git',EMBENCH_COMMIT)
    if a.workload in ['all','tiny']:
        command([sys.executable,HERE/'tiny/prepare.py','--tiny-dir',a.tiny_dir,'--tflm-dir',a.tflm_dir,
                 '--build-dir',a.build_dir/'tiny'])

def compile_c(a,source,target,flags):
    target.parent.mkdir(parents=True,exist_ok=True)
    try:s=source.relative_to(HERE)
    except ValueError:s=source
    args=[a.riscv_tools+'-gcc',*flags,'-I'+str(HERE),'-c',str(s),'-o',str(target)]
    fingerprint=hashlib.sha256((json.dumps(args)+source.read_text()+(HERE/'runtime.h').read_text()).encode()).hexdigest()
    stamp=target.with_suffix('.command-sha256')
    if not target.exists() or not stamp.exists() or stamp.read_text()!=fingerprint:
        command(args)
        stamp.write_text(fingerprint)
    return target

def common_objects(a,folder,tiny):
    folder.mkdir(parents=True,exist_ok=True)
    desc=folder/'descriptor.c'
    write(desc,f'const unsigned bench_is_tiny={int(tiny)};\nconst unsigned bench_gsf={a.gsf if not tiny else 0};\n')
    flags=[*RV,'-O3','-std=gnu99','-ffreestanding','-ffunction-sections','-fdata-sections']
    objs=[compile_c(a,HERE/'runtime.c',folder/'runtime.o',flags),compile_c(a,desc,folder/'descriptor.o',flags)]
    # Assembler uses the same ISA; no compressed instructions in startup.
    objs.append(compile_c(a,HERE/'startup.S',folder/'startup.o',RV))
    return objs

def convert(a,elf):
    data=elf.read_bytes()
    if data[:5]!=b'\x7fELF\x01' or struct.unpack_from('<H',data,18)[0]!=243:
        raise RuntimeError('Expected RV32 ELF: '+str(elf))
    if struct.unpack_from('<I',data,24)[0]!=0x100080:raise RuntimeError('Unexpected entry point')
    binary=elf.with_suffix('.bin');hexfile=elf.with_suffix('.hex')
    command([a.riscv_tools+'-objcopy','-O','binary',elf,binary])
    b=binary.read_bytes();b+=bytes((-len(b))%4)
    write(hexfile,''.join(f'{v[0]:08x}\n' for v in struct.iter_unpack('<I',b)))
    with elf.with_suffix('.dis').open('w') as f:command([a.riscv_tools+'-objdump','-d',elf],stdout=f)
    return dict(elf_sha256=digest(elf),binary_sha256=digest(binary),binary_bytes=len(b))

def embench_build(a):
    base=a.build_dir/'embench';objs=common_objects(a,base/'common',False)
    flags=[*RV,'-O3','-static','-std=gnu99','-fno-common','-nostartfiles','-ffreestanding',
           '-falign-functions=16','-falign-jumps=4',f'-DGLOBAL_SCALE_FACTOR={a.gsf}','-DWARMUP_HEAT=1',
           '-I'+str(a.embench_dir/'support'),'-I'+str(HERE/'embench')]
    for src in [a.embench_dir/'support/main.c',a.embench_dir/'support/beebsc.c',HERE/'embench/boardsupport.c']:
        objs.append(compile_c(a,src,base/'common'/(src.stem+'.o'),flags))
    names=sorted(p.name for p in (a.embench_dir/'src').iterdir() if p.is_dir())
    if a.workload not in ['all','embench']:
        if a.workload not in names:raise RuntimeError('Unknown workload: '+a.workload)
        names=[a.workload]
    def build_one(name):
        folder=base/name;more=[]
        for src in sorted((a.embench_dir/'src'/name).glob('*.c')):
            more.append(compile_c(a,src,folder/(src.stem+'.o'),flags))
        elf=folder/(name+'.elf')
        command([a.riscv_tools+'-gcc',*RV,'-static','-nostartfiles','-T',HERE/'link.ld',
                 '-Wl,--gc-sections','-Wl,-Map='+str(elf.with_suffix('.map')),*more,*objs,
                 '-Wl,--start-group','-lc','-lm','-lgcc','-Wl,--end-group','-o',elf])
        return name,dict(workload='embench',name=name,gsf=a.gsf,warmup_heat=1,
                         embench_commit=EMBENCH_COMMIT,**convert(a,elf))
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        result=dict(pool.map(build_one,names))
    return result

def tiny_build(a):
    folder=a.build_dir/'tiny';common_objects(a,folder,True)
    write(folder/'tiny_config.h',f'#define TINY_ITERATIONS {a.iterations}\n')
    command(['make','--no-print-directory','-C',HERE/'tiny','-j'+str(a.jobs),
             'BUILD='+str(folder),'TFLM_DIR='+str(a.tflm_dir),'TINY_DIR='+str(a.tiny_dir),
             'RISCV_TOOLS='+a.riscv_tools,'HOST_CXX='+a.host_cxx])
    return {'tiny':dict(workload='tiny',name='ad01',iterations=a.iterations,
                       assets=json.loads((folder/'assets.json').read_text()),**convert(a,folder/'tiny.elf'))}

def build(a):
    metadata={}
    if a.workload!='tiny':metadata.update(embench_build(a))
    if a.workload in ['all','tiny']:metadata.update(tiny_build(a))
    config=dict(core=CORE,ibex_config=a.ibex_config if CORE['core']=='ibex' else None,harts=1,cache=False,
                ram_bytes=1048576,ram_base='0x00100000',memory_response_cycles=1,
                isa='rv32im',abi='ilp32',clock_mhz_assumed=a.clock_mhz,
                compiler=subprocess.check_output([a.riscv_tools+'-gcc','--version'],text=True).splitlines()[0],
                targets=metadata)
    write(a.build_dir/'config.json',json.dumps(config,indent=2)+'\n')
    return metadata

def fields(line):return dict(re.findall(r'(\w+)=([^\s]+)',line))
def exactly(text,prefix):
    lines=[x for x in text.splitlines() if x.startswith(prefix+' ')]
    if len(lines)!=1:raise ValueError(f'Expected one {prefix}, found {len(lines)}')
    return fields(lines[0])

def parse_result(text,meta,config):
    sim=exactly(text,'BENCH_SIM_CONFIG');audit=exactly(text,'BENCH_AUDIT');exit_=exactly(text,'BENCH_SIM_EXIT')
    if sim['core']!=CORE['core'] or int(sim['harts'])!=1 or int(sim['cache'])!=0:raise ValueError('RTL configuration mismatch')
    if int(sim['memory_bytes'])!=1048576 or int(sim['memory_response_cycles'])!=1:raise ValueError('RAM configuration mismatch')
    if CORE['core']=='ibex':
        expected=(2,0,0) if config['ibex_config']=='small' else (3,1,1)
        if tuple(int(sim[k]) for k in ['rv32m','branch_target_alu','writeback_stage'])!=expected:raise ValueError('Ibex configuration mismatch')
    elif int(sim['corev_pulp']) or int(sim['fpu']):raise ValueError('CV32E40P extension configuration mismatch')
    if int(exit_['exit'])!=0:raise ValueError('Program returned failure')
    if int(audit['windows'])!=1 or int(audit['output_during_measurement'])!=0 or int(audit['output_writes'])==0:raise ValueError('Measurement/output audit failed')
    if 'BENCH_TRAP' in text or 'TINY_ERROR' in text:raise ValueError('Target error/trap')
    if meta['workload']=='tiny':
        stats=exactly(text,'TINY_STATS');total=exactly(text,'TINY_TOTAL');arena=exactly(text,'TINY_ARENA')
        passed=exactly(text,'TINY_PASS');allpassed=exactly(text,'TINY_ALL_PASS')
        checks=[fields(x) for x in text.splitlines() if x.startswith('TINY_CHECK ')]
        if len(checks)!=3 or {int(c['fixture']) for c in checks}!={0,1,2}:raise ValueError('Missing fixtures')
        expected=[('074ac5f5','413ad196'),('f29d8186','4124c420'),('5684552e','412dd03c')]
        for c in checks:
            h,s=expected[int(c['fixture'])]
            if int(c['mismatches']) or c['hash']!=h or c['score_bits']!=s or c['expected_score_bits']!=s:raise ValueError('Golden mismatch')
        if int(stats['iterations'])!=meta['iterations'] or int(total['total_inferences'])!=meta['iterations']:raise ValueError('Iteration count mismatch')
        if int(arena['reserved_bytes'])!=65536 or not 0<int(arena['used_bytes'])<=65536:raise ValueError('Arena bounds')
        if passed.get('measured_output')!='PASS' or int(passed['exit'])!=0 or int(passed['fixtures'])!=3:raise ValueError('Final output check failed')
        if int(allpassed['uart_after_measurement'])!=1:raise ValueError('Output ordering failed')
        result=dict(checks=checks,arena=arena,iterations=meta['iterations'])
    else:
        stats=exactly(text,'EMBENCH_STATS');passed=exactly(text,'EMBENCH_PASS')
        if int(stats['gsf'])!=meta['gsf'] or int(passed['exit'])!=0:raise ValueError('Embench verification failed')
        result=dict(gsf=meta['gsf'])
    cycles=int(stats['cycles']);instructions=int(stats['instructions'])
    if not cycles>0 or not instructions>0:raise ValueError('Zero performance counter')
    if cycles!=int(audit['cycles']) or instructions!=int(audit['instructions']):raise ValueError('Software counters disagree with RTL audit')
    if meta['workload']=='tiny' and (int(total['window_cycles'])!=cycles or int(total['instructions'])!=instructions):raise ValueError('Tiny totals disagree')
    result.update(cycles=cycles,instructions=instructions,ipc=instructions/cycles,sim_config=sim,audit=audit)
    if meta['workload']=='tiny':
        result.update(cycles_per_inference=cycles/meta['iterations'],
                      ms_per_inference=cycles/meta['iterations']/(config['clock_mhz_assumed']*1000),
                      inferences_per_second=meta['iterations']*config['clock_mhz_assumed']*1e6/cycles)
    return result

def run_one(a,name,meta,sim,config):
    if name=='tiny':elf=a.build_dir/'tiny/tiny.elf'
    else:elf=a.build_dir/'embench'/name/(name+'.elf')
    folder=a.build_dir/'runs'/name;folder.mkdir(parents=True,exist_ok=True)
    for log in ['program.log','ibex_simple_system.log']:
        p=folder/log
        if p.exists():p.unlink()
    result=dict(passed=False,name=name,target=meta,config={k:v for k,v in config.items() if k!='targets'})
    args=[str(sim),'+memhex='+str(elf.with_suffix('.hex')),'+ibex_tracer_enable=0','+max_cycles=2000000000']
    start=time.monotonic()
    try:
        completed=subprocess.run(args,cwd=folder,capture_output=True,text=True,timeout=a.timeout)
        console=completed.stdout+completed.stderr
        result['sim_returncode']=completed.returncode
    except subprocess.TimeoutExpired as e:
        console=(e.stdout or b'').decode() if isinstance(e.stdout,bytes) else (e.stdout or '')
        result['error']='simulation timeout';completed=None
    for log in ['program.log','ibex_simple_system.log']:
        p=folder/log
        if p.exists():console+='\n'+p.read_text()
    write(folder/'console.txt',console)
    result['host_wall_seconds']=time.monotonic()-start
    if completed is not None:
        try:
            if completed.returncode:raise ValueError('Simulator did not exit successfully')
            result.update(parse_result(console,meta,config));result['passed']=True
        except (ValueError,KeyError) as e:result['error']=str(e)
    write(folder/'result.json',json.dumps(result,indent=2)+'\n')
    print(f"{CORE['core']} {name}: {'PASS' if result['passed'] else 'FAIL'} cycles={result.get('cycles')} instructions={result.get('instructions')} {result.get('error','')}",flush=True)
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['prepare','build','sim','run'])
    p.add_argument('--workload',default='all',help='all, embench, tiny, or an Embench benchmark name')
    p.add_argument('--riscv-tools',default='riscv64-unknown-elf')
    p.add_argument('--verilator',default='verilator')
    p.add_argument('--host-cxx',default='g++')
    p.add_argument('--jobs',type=int,default=2)
    p.add_argument('--gsf',type=int,default=12)
    p.add_argument('--iterations',type=int,default=12)
    p.add_argument('--clock-mhz',type=float,default=80)
    p.add_argument('--timeout',type=float,default=1800)
    p.add_argument('--ibex-config',choices=['small','maxperf'],default='small')
    p.add_argument('--build-dir',type=Path)
    for dep in ['embench','tiny','tflm']:p.add_argument('--'+dep+'-dir',type=Path,default=HERE/'.deps'/dep)
    a=p.parse_args()
    if not 0<a.iterations<2**32 or not 0<a.gsf<2**32 or not a.jobs>0 or not a.clock_mhz>0:p.error('positive parameters required')
    if not a.build_dir:a.build_dir=HERE/'build'/a.ibex_config
    for key in ['build_dir','embench_dir','tiny_dir','tflm_dir']:setattr(a,key,getattr(a,key).resolve())
    if a.action=='sim':build_sim.build(HERE,a.build_dir/'sim',a.verilator,a.jobs,a.ibex_config);return
    prepare(a)
    if a.action=='prepare':return
    build(a)
    if a.action=='build':return
    sim=build_sim.build(HERE,a.build_dir/'sim',a.verilator,a.jobs,a.ibex_config)
    config=json.loads((a.build_dir/'config.json').read_text())
    results=[]
    for name,meta in config['targets'].items():results.append(run_one(a,name,meta,sim,config))
    summary=dict(passed=all(r['passed'] for r in results),core=CORE,results=results)
    write(a.build_dir/'summary.json',json.dumps(summary,indent=2)+'\n')
    if not summary['passed']:raise SystemExit(1)

if __name__=='__main__':main()
