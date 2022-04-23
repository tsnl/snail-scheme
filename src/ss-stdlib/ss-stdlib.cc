#include "ss-jit/std.hh"
#include "ss-jit/vm.hh"

static_assert(sizeof(void*) == 8, "Expected 64-bit systems only");

extern "C" {

    void SsrtReq_exportAll(void* vm) {
        bind_standard_procedures(static_cast<VirtualMachine*>(vm));
    }

}
