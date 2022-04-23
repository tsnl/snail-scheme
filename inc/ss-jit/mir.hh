#pragma once

#include "ss-core/object.hh"

namespace ss {

    using VmExpID = size_t;

    ///
    // VmExp data: each expression either stores a VM instruction or a constant
    // All VmExps are are stored in a flat table in the 'VirtualMachine'.
    //  - this ensures traversal during interpretation is of similar efficiency to bytecode with padding
    //  - TODO: do we need to traverse this structure to perform GC? cf Ch4
    //

    enum class VmExpKind: VmExpID {
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
        Return,
        Define,
        // todo: implement a CFFI function call instruction
    };
    union VmExpArgs {
        struct {} i_halt;
        struct { OBJECT var; VmExpID x; } i_refer;
        struct { OBJECT constant; VmExpID x; } i_constant;
        struct { VmExpID body; VmExpID x; } i_close;
        struct { VmExpID next_if_t; VmExpID next_if_f; } i_test;
        struct { OBJECT var; VmExpID x; } i_assign;
        struct { VmExpID x; } i_conti;
        struct { OBJECT s; OBJECT var; } i_nuate;
        struct { VmExpID x; VmExpID ret; } i_frame;
        struct { VmExpID x; } i_argument;
        struct { OBJECT var; VmExpID next; } i_define;
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

    ///
    // VmProgram: 
    // represents a path of execution in the ordered node graph: just an (s, t) pair corresponding to 1 expression.
    //

    struct VmProgram {
        VmExpID s;
        VmExpID t;  // must be a 'halt' expression so we can read the accumulator
    };

}