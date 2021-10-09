#pragma once

#include "object.hh"

class VirtualMachine;

VirtualMachine* create_vm();
void add_file_to_vm(VirtualMachine* vm, std::string const& file_name, std::vector<Object*> objs);
