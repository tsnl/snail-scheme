#pragma once

#include <ostream>
#include "ss-core/object.hh"
#include "std.hh"
#include "ss-core/gc.hh"
#include "vrom.hh"

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

    // program_vm tells the VM to execute this VRom.
    // if multiple files are added, they are executed in the order in which they 
    // were added to the VRom.
    void program_vm(VirtualMachine* vm, VRom&& rom);

    // getting GC front-end:
    // since only single-threaded, just one thread front-end
    static_assert(GC_SINGLE_THREADED_MODE);
    GcThreadFrontEnd* vm_gc_tfe(VirtualMachine* vm);

    // getting 'default' init_var_rib, used to provide globals
    // TODO: switch to a more efficient O(1) array lookup mechanism for globals
    OBJECT vm_default_init_var_rib(VirtualMachine* vm);

    // bind_builtin adds a new definition to an initializer list that constructs the
    // builtin environment.
    void define_builtin_value_in_vm(VirtualMachine* vm, std::string name_str, OBJECT object);
    void define_builtin_procedure_in_vm(VirtualMachine* vm, std::string name_str, EXT_CallableCb callback, std::vector<std::string> arg_names);

    // sync_execute_vm uses std::this_thread to begin the VM execution.
    void sync_execute_vm(VirtualMachine* vm, bool print_each_line);

    // dump_vm prints the VM's state for debug information.
    void dump_vm(VirtualMachine* vm, std::ostream& out);

}