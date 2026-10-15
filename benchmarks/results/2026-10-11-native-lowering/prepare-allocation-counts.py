import json
import os
import experiment as e
host=(e.ROOT/'src/native.c').read_text()
host=host.replace('static uint64_t allocations, collection_interval;', 'static uint64_t allocations, collection_interval;\nstatic uint64_t measured_allocations, measured_bytes, measured_arrays;')
host=host.replace('static void *try_allocate(uint64_t size) {','static void *try_allocate(uint64_t size) {\n    measured_allocations++; measured_bytes += size;')
host=host.replace('uint64_t native_array_new(uint64_t type, uint32_t length, uint64_t initial) {','uint64_t native_array_new(uint64_t type, uint32_t length, uint64_t initial) {\n    measured_arrays++;')
host=host.replace('    return status;', '    fprintf(stderr, "allocations=%llu requested_bytes=%llu array_new=%llu heap_bytes=%zu collections=%zu\\n",\n        (unsigned long long)measured_allocations, (unsigned long long)measured_bytes,\n        (unsigned long long)measured_arrays, GC_get_heap_size(), (size_t)GC_get_gc_no());\n    return status;')
path=e.BUILD/'allocation-counts.c'
path.write_text(host)
flags=['-lgc','-lm','-ldl','-lpthread','-I',os.environ['BDWGC_INCLUDE'],
       '-L',os.environ['BDWGC_LIB'],'-Wl,-rpath,'+os.environ['BDWGC_LIB']]
records={}
for workload in e.WORKLOADS:
    command=['clang','-O3','-flto','-fuse-ld=lld',e.BUILD/f'{workload}.ll',path,e.BUILD/'runtime.a',*flags,'-o',e.BUILD/f'{workload}-counts']
    e.run(command)
    record=e.sample(workload,'counts')
    record['diagnostic_only']=True
    record['build_command']=list(map(str,command))
    records[workload]=record
    (e.BUILD/'allocation-counts.json').write_text(json.dumps(records,indent=2)+'\n')
    print(workload,record['stderr'],flush=True)
