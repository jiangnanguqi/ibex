#!/usr/bin/env python3
"""Check rejection paths using real faulted target programs and saved reports."""
import argparse,copy,json,re,subprocess
from pathlib import Path
import port

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build-dir',type=Path,required=True)
    p.add_argument('--riscv-tools',default='riscv64-unknown-elf')
    p.add_argument('--timeout',type=int,default=300)
    a=p.parse_args();a.build_dir=a.build_dir.resolve()
    config=json.loads((a.build_dir/'config.json').read_text())
    base=a.build_dir/'negative';base.mkdir(exist_ok=True)
    slre=a.build_dir/'embench/slre'
    common=a.build_dir/'embench/common'
    objs=[*slre.glob('*.o'),*common.glob('*.o')]
    outcomes=[]
    def compile_(source,target,flags):
        port.command([a.riscv_tools+'-gcc',*port.RV,'-O3','-std=gnu99','-ffreestanding',
                      '-ffunction-sections','-fdata-sections','-I'+str(port.HERE),*flags,'-c',source,'-o',target])
    def link(objects,elf,extra=()):
        port.command([a.riscv_tools+'-gcc',*port.RV,'-static','-nostartfiles','-T',port.HERE/'link.ld',
                      '-Wl,--gc-sections',*extra,*objects,'-Wl,--start-group','-lc','-lm','-lgcc',
                      '-Wl,--end-group','-o',elf])
        port.convert(a,elf)
    def fault(name,elf,meta,required):
        folder=base/name;folder.mkdir(exist_ok=True)
        completed=subprocess.run([str(a.build_dir/'sim/Vbench'),'+memhex='+str(elf.with_suffix('.hex')),
                                  '+ibex_tracer_enable=0','+max_cycles=200000000'],cwd=folder,
                                 capture_output=True,text=True,timeout=a.timeout)
        text=completed.stdout+completed.stderr
        for log in ['program.log','ibex_simple_system.log']:
            f=folder/log
            if f.exists():text+='\n'+f.read_text()
        port.write(folder/'console.txt',text)
        assert required in text,(name,'expected failure was not observed',text)
        rejected=False
        try:
            if completed.returncode:raise ValueError('Simulator returned failure')
            port.parse_result(text,meta,config)
        except (ValueError,KeyError) as e:rejected=True;reason=str(e)
        assert rejected,(name,'faulted target accepted')
        out=dict(test=name,passed=True,expected_rejection=True,sim_returncode=completed.returncode,reason=reason,
                 binary_sha256=port.digest(elf.with_suffix('.bin')))
        port.write(folder/'result.json',json.dumps(out,indent=2)+'\n');outcomes.append(out)
        print(name,'rejected as expected',flush=True)

    source=base/'force_verify_fail.c';source.write_text('int __wrap_verify_benchmark(int value) { (void)value; return 0; }\n')
    obj=base/'force_verify_fail.o';compile_(source,obj,[])
    elf=base/'verify-failure.elf';link([*objs,obj],elf,['-Wl,--wrap=verify_benchmark'])
    fault('verify-failure',elf,config['targets']['slre'],'EMBENCH_FAIL exit=1')

    source=base/'output_in_measurement.c'
    source.write_text((port.HERE/'runtime.c').read_text().replace('CSR_WRITE(0x320,0);',
                         "CSR_WRITE(0x320,0); bench_putchar('!');",1))
    obj=base/'output_in_measurement.o';compile_(source,obj,[])
    elf=base/'output-in-measurement.elf';link([o for o in objs if o.name!='runtime.o']+[obj],elf)
    fault('output-in-measurement',elf,config['targets']['slre'],'Output occurred with performance counters enabled')

    tiny=a.build_dir/'tiny';golden=(tiny/'golden.h').read_text()
    match=re.search(r'(kExpected\[3\]\[640\]\s*=\s*\{\s*\{\s*)(-?\d+)',golden)
    assert match
    value=int(match.group(2));value=value+1 if value<127 else value-1
    golden=golden[:match.start(2)]+str(value)+golden[match.end(2):]
    (base/'golden.h').write_text(golden)
    obj=base/'tiny_main_bad_golden.o'
    port.command([a.riscv_tools+'-g++',*port.RV,'-O3','-std=c++17','-fno-exceptions','-fno-rtti',
                  '-ffunction-sections','-fdata-sections','-DTINY_ITERATIONS=12',
                  '-I'+str(base),'-I'+str(port.HERE/'tiny'),'-c',port.HERE/'tiny/benchmark_main.cc','-o',obj])
    objects=[o for o in sorted((tiny/'rv').rglob('*.o')) if o.name!='benchmark_main.o']
    objects += [tiny/'runtime.o',tiny/'startup.o',tiny/'descriptor.o',obj]
    elf=base/'tiny-bad-golden.elf';link(objects,elf)
    fault('tiny-bad-golden',elf,config['targets']['tiny'],'fixture=0 mismatches=1')

    # Mutate independent dimensions of positive reports to ensure the parser
    # cannot turn missing checks, zero counters or a different RTL into a pass.
    positive=(a.build_dir/'runs/tiny/console.txt').read_text()
    mutations={
      'missing_fixture':'\n'.join(l for l in positive.splitlines() if not l.startswith('TINY_CHECK hart=0 fixture=2')),
      'wrong_score':positive.replace('score_bits=413ad196','score_bits=00000000',1),
      'zero_cycles':re.sub(r'(TINY_STATS[^\n]* cycles=)\d+',r'\g<1>0',positive),
      'counter_disagreement':re.sub(r'(BENCH_AUDIT[^\n]* instructions=)\d+',r'\g<1>1',positive),
      'missing_audit':'\n'.join(l for l in positive.splitlines() if not l.startswith('BENCH_AUDIT')),
      'wrong_cache':positive.replace('cache=0','cache=1',1),
    }
    for name,text in mutations.items():
        try:port.parse_result(text,config['targets']['tiny'],config)
        except (ValueError,KeyError):outcomes.append(dict(test=name,passed=True,expected_rejection=True))
        else:raise AssertionError(name+' was accepted')
    port.write(base/'summary.json',json.dumps(dict(passed=True,tests=outcomes),indent=2)+'\n')

if __name__=='__main__':main()
