"""Profile the validated V8 workload separately from benchmark samples."""
import json
import experiment as e
output=e.BUILD/'v8-profile-output.wat'
command=['taskset','-c','2','node','--prof','--logfile='+str(e.BUILD/'v8.log'),
         '--no-logfile-per-isolate','--trace-gc-nvp','--no-warnings',
         e.ROOT/'scripts/run-wasi.mjs',e.BUILD/'compiler.wasm',e.INPUT,
         e.INPUT/'benchmarks/compile-self.scm',output,'v8-profile']
result=e.run(command,cwd='/tmp')
assert e.digest(output)==e.REFERENCE
(e.BUILD/'v8-gc.txt').write_text(result.stdout)
(e.BUILD/'v8-profile.json').write_text(json.dumps({'command':list(map(str,command)),
    'stderr':result.stderr,'sha256':e.digest(output),'diagnostic_only':True},indent=2)+'\n')
profile=e.run(['node','--prof-process',e.BUILD/'v8.log'])
(e.BUILD/'v8-profile.txt').write_text(profile.stdout)
print('validated CPU2 V8 profile')
