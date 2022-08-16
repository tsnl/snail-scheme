#pragma once

namespace ss {

    class VirtualMachine;
    using VirtualMachineStandardProcedureBinder = void(*)(VirtualMachine* vm);

    void bind_standard_procedures(VirtualMachine* vm);

}