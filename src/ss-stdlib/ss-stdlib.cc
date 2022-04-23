namespace ss {
    #include "snail-scheme/std.hh"
    #include "snail-scheme/vm.hh"
}

extern "C" {

    void SsrtReq_exportAll(void* vm) {
        bind_standard_procedures(static_cast<VirtualMachine*>(vm));
    }

}
