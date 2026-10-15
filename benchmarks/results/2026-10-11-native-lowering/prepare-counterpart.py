import experiment as e
import shutil
baseline=e.BUILD/'baseline-src'
shutil.copytree(e.ROOT/'src',baseline,dirs_exist_ok=True)
(baseline/'snail-scheme/llvm.sld').write_text(e.run(['git','show','HEAD:src/snail-scheme/llvm.sld'],cwd=e.ROOT).stdout)
for label,source in [('baseline',baseline),('fixed',e.BUILD/'direct-src')]:
    prefix=e.BUILD/f'counterpart-{label}'
    shutil.copyfile(e.BUILD/'counterpart.wat',prefix.with_suffix('.wat'))
    e.run(['chibi-scheme','-I',source,e.BUILD/'translate.scm',prefix])
    e.run(['clang','-O3','-S',prefix.with_suffix('.ll'),'-o',prefix.with_suffix('.s')])
e.run(['clang','-O3','-S',e.BUILD/'counterpart.c','-o',e.BUILD/'counterpart-c.s'])
for workload in e.WORKLOADS:
    result=e.run(['chibi-scheme','-h512M','-I',e.ROOT/'src',e.BUILD/'function-names.scm',e.BUILD/f'{workload}.wat'])
    (e.BUILD/f'{workload}-names.scm').write_text(result.stdout)
