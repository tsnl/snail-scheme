#pragma once

#include <ostream>
#include "ss-core/object.hh"
#include "std.hh"
#include "ss-core/gc.hh"
#include "vcode.hh"

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

    // program_vm tells the VM to execute this VCode.
    // if multiple files are added, they are executed in the order in which they 
    // were added to the VCode.
    void program_vm(VirtualMachine* vm, VCode&& rom);

    // getting GC front-end:
    // since only single-threaded, just one thread front-end
    static_assert(GC_SINGLE_THREADED_MODE);
    GcThreadFrontEnd* vm_gc_tfe(VirtualMachine* vm);

    // sync_execute_vm uses std::this_thread to begin the VM execution.
    void sync_execute_vm(VirtualMachine* vm, bool print_each_line);

    // dump_vm prints the VM's state for debug information.
    void dump_vm(VirtualMachine* vm, std::ostream& out);

}