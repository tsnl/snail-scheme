#pragma once

class VirtualMachine;
using VirtualMachineStandardProcedureBinder = void(*)(VirtualMachine* vm);

void bind_standard_procedures(VirtualMachine* vm);