#pragma once

#include <ostream>
#include "ss-core/object.hh"
#include "ss-core/gc.hh"
#include "ss-jit/compiler.hh"
#include "ss-jit/std.hh"
#include "ss-jit/vcode.hh"

namespace ss {

    //
    // Type declarations/early definitions:
    //

    class VirtualMachine;

    //
    // Virtual machine:
    //

    // create_vm instantiates a VM.
    VirtualMachine* create_vm(
        Gc* gc,
        VirtualMachineStandardProcedureBinder binder = bind_standard_procedures,
        int init_reserved_file_count = 32
    );

    // destroy_vm destroys a VM.
    // TODO: clean up after destroying VM.
    void destroy_vm(VirtualMachine* vm);

    // getting GC front-end:
    // since only single-threaded, just one thread front-end
    static_assert(GC_SINGLE_THREADED_MODE);
    GcThreadFrontEnd* vm_gc_tfe(VirtualMachine* vm);

    void define_builtin_procedure_in_vm(
        VirtualMachine* vm, 
        std::string proc_name,
        EXT_CallableCb callable_cb,
        std::vector<std::string> arg_names,
        std::string docstring_more = ""
    );

    // Getting VM compiler:
    // Used to bind globals, compile source code.
    // Should only be directly used by the linker: each library has its own env, and
    // its own compiler; the linker splices libraries into the main program.
    Compiler* vm_compiler(VirtualMachine* vm);

    // sync_execute_vm uses std::this_thread to begin the VM execution.
    void sync_execute_vm(VirtualMachine* vm, bool print_each_line);

    // dump_vm prints the VM's state for debug information.
    void dump_vm(VirtualMachine* vm, std::ostream& out);

}