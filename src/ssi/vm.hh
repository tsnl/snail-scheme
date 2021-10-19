#pragma once

#include <ostream>
#include "object.hh"

//
// Type declarations/early definitions:
//

class VirtualMachine;
using VmExpID = size_t;

//
// Virtual machine:
//

VirtualMachine* create_vm();
void add_file_to_vm(VirtualMachine* vm, std::string const& file_name, std::vector<Object*> line_code_obj_list);
void sync_execute_vm(VirtualMachine* vm);
void dump_vm(VirtualMachine* vm, std::ostream& out);
