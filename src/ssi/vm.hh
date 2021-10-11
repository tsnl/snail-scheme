#pragma once

#include <ostream>
#include "object.hh"

#include "vm-exp.hh"
#include "vm-stack.hh"

class VirtualMachine;

VirtualMachine* create_vm();
void add_file_to_vm(VirtualMachine* vm, std::string const& file_name, std::vector<Object*> line_code_obj_list);
void sync_execute_vm(VirtualMachine* vm, bool print_each_line);
void dump_vm(VirtualMachine* vm, std::ostream& out);
