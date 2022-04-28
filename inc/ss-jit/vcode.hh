#pragma once

#include <vector>
#include <string>

#include "ss-core/object.hh"

///
// Expressions
//

namespace ss {

    ///
    // VmExp: each expression is a VM instruction.
    // Name comes from CPS convention + 'x' for 'next expression' register in VM.
    // All VmExps are are stored in a flat table in the 'VirtualMachine'.
    //  - this ensures traversal during interpretation is of similar efficiency to bytecode with padding
    //  - TODO: do we need to traverse this structure to perform GC? cf Ch4
    //

    using VmExpID = my_ssize_t;

    enum class VmExpKind: VmExpID {
        Halt,
        ReferLocal,
        ReferFree,
        ReferGlobal,
        Constant,
        Close,
        Test,
        AssignLocal,
        AssignFree,
        AssignGlobal,
        Conti,
        Nuate,
        Frame,
        Argument,
        Apply,
        Return,
        Define,
        Indirect,
        Box,
        Shift
    };
    union VmExpArgs {
        struct {} i_halt;
        struct { size_t n; VmExpID x; } i_refer;
        struct { OBJECT obj; VmExpID x; } i_constant;
        struct { size_t vars_count; VmExpID body; VmExpID x; } i_close;
        struct { VmExpID next_if_t; VmExpID next_if_f; } i_test;
        struct { size_t n; VmExpID x; } i_assign;                           // see three-imp p.105
        struct { VmExpID x; } i_conti;
        struct { OBJECT stack; VmExpID x; } i_nuate;
        struct { VmExpID x; VmExpID ret; } i_frame;
        struct { VmExpID x; } i_argument;
        struct { OBJECT var; VmExpID next; } i_define;
        struct {} i_apply;
        struct { size_t n; } i_return;
        struct { VmExpID x; } i_indirect;                                   // see three-imp p.105
        struct { my_ssize_t n; VmExpID x; } i_box;                          // see three-imp p.105
        struct { my_ssize_t n; my_ssize_t m; VmExpID x; } i_shift;          // see three-imp p.111
    };
    struct VmExp {
        VmExpKind kind;
        VmExpArgs args;
    public:
        explicit VmExp(VmExpKind new_kind)
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

    //
    // VScript: a collection of programs-- one per line, and the source code object (may be reused, e.g. 'quote')
    //

    struct VScript {
        std::vector<OBJECT> line_code_objs;
        std::vector<VmProgram> line_programs;

        VScript(std::vector<OBJECT> obj, std::vector<VmProgram> line_programs)
        :   line_code_objs(obj),
            line_programs(line_programs)
        {}
        explicit VScript(VScript&& other) noexcept
        :   line_code_objs(std::move(other.line_code_objs)),
            line_programs(std::move(other.line_programs))
        {}
    };

}

///
// VCode = container of expressions
//

namespace ss {

    class VCode {
    // Data members, constructor:
    public:
        inline static constexpr size_t DEFAULT_RESERVED_FILE_COUNT = 1024;
    private:
        std::vector<VmExp> m_exps;
        std::vector<VScript> m_files;
    public:
        explicit VCode(size_t reserved_file_count = DEFAULT_RESERVED_FILE_COUNT);
        explicit VCode(VCode&& other) noexcept;
    
    // Adding script: these are run in the order in which they are added.
    void add_script(std::string const& file_name, VScript&& script);
    
    // Core getters and setters:
    public:
        std::vector<VmExp>& exps() { return m_exps; };
        std::vector<VScript>& files() { return m_files; };
        VmExp& operator[] (VmExpID exp_id) { return m_exps[exp_id]; }
    
    // creating VM expressions:
    private:
        std::pair<VmExpID, VmExp&> help_new_vmx(VmExpKind kind);
    public:
        VmExpID new_vmx_halt();
        VmExpID new_vmx_refer_local(size_t n, VmExpID x);
        VmExpID new_vmx_refer_free(size_t n, VmExpID x);
        VmExpID new_vmx_refer_global(size_t n, VmExpID x);
        VmExpID new_vmx_constant(OBJECT constant, VmExpID next);
        VmExpID new_vmx_close(size_t vars_count, VmExpID body, VmExpID next);
        VmExpID new_vmx_test(VmExpID next_if_t, VmExpID next_if_f);
        VmExpID new_vmx_conti(VmExpID x);
        VmExpID new_vmx_nuate(OBJECT stack, VmExpID x);
        VmExpID new_vmx_frame(VmExpID x, VmExpID ret);
        VmExpID new_vmx_argument(VmExpID x);
        VmExpID new_vmx_apply();
        VmExpID new_vmx_return(size_t n);
        VmExpID new_vmx_define(OBJECT var, VmExpID next);
        VmExpID new_vmx_box(my_ssize_t n, VmExpID next);
        VmExpID new_vmx_indirect(VmExpID next);
        VmExpID new_vmx_assign_local(size_t n, VmExpID next);
        VmExpID new_vmx_assign_free(size_t n, VmExpID next);
        VmExpID new_vmx_assign_global(size_t gn, VmExpID next);
        VmExpID new_vmx_shift(my_ssize_t n, my_ssize_t m, VmExpID x);

    public:
        void flash(VCode&& other);

    // dump:
    public:
        void dump(std::ostream& out) const;
    private:        
        void print_all_exps(std::ostream& out) const;
        void print_one_exp(VmExpID exp_id, std::ostream& out) const;
        void print_all_files(std::ostream& out) const;
    };

}   // namespace ss

///
// VObject: compiled VCode (with 'include's expanded) + tabular globals/imports/exports
//

namespace ss {

    class VModule {

    };

}