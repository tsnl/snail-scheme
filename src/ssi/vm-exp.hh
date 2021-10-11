#pragma once

#include <cstddef>
#include "vm-stack.hh"

//
// VmExp data: each expression either stores a VM instruction or a constant
// All VmExps are are stored in a flat table in the 'VirtualMachine'.
//  - this ensures traversal during interpretation is of similar efficiency to bytecode with padding
//  - TODO: do we need to traverse this structure to perform GC? cf Ch4
//

using VmExpID = size_t;

enum class VmExpKind: VmExpID {
    // Instructions:
    Halt,
    Refer,
    Constant,
    Close,
    Test,
    Assign,
    Conti,
    Nuate,
    Frame,
    Argument,
    Apply,
    Return
};
union VmExpArgs {
    struct {} i_halt;
    struct { Object* var; VmExpID x; } i_refer;
    struct { Object* constant; VmExpID x; } i_constant;
    struct { Object* vars; VmExpID body; VmExpID x; } i_close;
    struct { VmExpID next_if_t; VmExpID next_if_f; } i_test;
    struct { Object* var; VmExpID x; } i_assign;
    struct { VmExpID x; } i_conti;
    struct { VMA_CallFrameObject* s; Object* var; } i_nuate;
    struct { VmExpID x; VmExpID ret; } i_frame;
    struct { VmExpID x; } i_argument;
    struct {} i_apply;
    struct {} i_return_;
};
struct VmExp {
    VmExpKind kind;
    VmExpArgs args;

    VmExp(VmExpKind new_kind)
    :   kind(new_kind),
        args()
    {}
};
static_assert(
    sizeof(VmExp) == 4*sizeof(size_t), 
    "Unexpected sizeof(VmExp)"
);
