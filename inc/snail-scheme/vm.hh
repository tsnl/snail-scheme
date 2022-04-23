#pragma once

#include <ostream>
#include "object.hh"
#include "std.hh"
#include "gc.hh"

//
// Type declarations/early definitions:
//

class VirtualMachine;
using VmExpID = size_t;

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

// add_file_to_vm tells the VM to execute this file.
// if multiple files are added, they are executed in the order in which they 
// were added.
void add_file_to_vm(
    VirtualMachine* vm, 
    std::string const& file_name, 
    std::vector<OBJECT> line_code_obj_list
);

// getting GC front-end:
// since only single-threaded, just one thread front-end
static_assert(GC_SINGLE_THREADED_MODE);
GcThreadFrontEnd* vm_gc_tfe(VirtualMachine* vm);

// bind_builtin adds a new definition to an initializer list that constructs the
// builtin environment.
void define_builtin_value_in_vm(VirtualMachine* vm, std::string name_str, OBJECT object);
void define_builtin_procedure_in_vm(VirtualMachine* vm, std::string name_str, EXT_CallableCb callback, std::vector<std::string> arg_names);

// sync_execute_vm uses std::this_thread to begin the VM execution.
void sync_execute_vm(VirtualMachine* vm, bool print_each_line);

// dump_vm prints the VM's state for debug information.
void dump_vm(VirtualMachine* vm, std::ostream& out);
