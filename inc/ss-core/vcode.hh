#pragma once

#include <vector>
#include <string>
#include <queue>

#include "ss-core/object.hh"
#include "ss-core/common.hh"
#include "ss-core/defn.hh"
#include "ss-core/pinvoke.hh"

///
// Expressions
//

namespace ss {

    ///
    // VmExp: each expression is a VM instruction.
    // Term 'expression' rather than 'instruction' comes from CPS convention: 'x' for 'next expression' register in VM.
    // All VmExps are are stored in a flat table in the 'VirtualMachine'.
    //  - this ensures traversal during interpretation is of similar efficiency to bytecode with padding
    //  - TODO: do we need to traverse this structure to perform GC? cf Ch4
    //

    using VmExpID = ssize_t;

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
        Shift,
        PInvoke
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
        struct { VmExpID fn_body_x; VmExpID post_ret_x; } i_frame;
        struct { VmExpID x; } i_argument;
        struct { OBJECT var; VmExpID next; } i_define;
        struct {} i_apply;
        struct { size_t n; } i_return;
        struct { VmExpID x; } i_indirect;                                   // see three-imp p.105
        struct { ssize_t n; VmExpID x; } i_box;                          // see three-imp p.105
        struct { ssize_t n; ssize_t m; VmExpID x; } i_shift;          // see three-imp p.111
        struct { ssize_t n; size_t proc_id; VmExpID x; } i_pinvoke;
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
    // VSubr: a collection of programs-- one per line, and the source code object (may be reused, e.g. 'quote')
    //

    struct VSubr {
        std::vector<OBJECT> line_code_objs;
        std::vector<VmProgram> line_programs;
        std::string name;

        VSubr(std::string name, std::vector<OBJECT> obj, std::vector<VmProgram> line_programs)
        :   line_code_objs(obj),
            line_programs(line_programs),
            name(name)
        {}
        explicit VSubr(VSubr&& other) noexcept
        :   line_code_objs(std::move(other.line_code_objs)),
            line_programs(std::move(other.line_programs)),
            name(std::move(other.name))
        {}
    };

}

///
// VCode = instructions + globals/imports
// - basically an SO file: contains a global symbol table, definitions use an index that will be
//   rewritten on linking.
// - also an output container for linker: can link multiple VCodeObject instances into one
//   VCodeObject.
// - used as compiler output and VM input to allow dynamic compilation (e.g. for conti/nuate)
//

namespace ss {

    class VCode {
    // Data members, constructor:
    public:
        inline static constexpr size_t DEFAULT_RESERVED_FILE_COUNT = 1024;
    private:
        std::vector<VmExp> m_exps;
        std::vector<VSubr> m_subrs;
        DefTable m_def_tab;
        PlatformProcTable m_pproc_tab;

    public:
        explicit VCode(size_t reserved_file_count = DEFAULT_RESERVED_FILE_COUNT);
        explicit VCode(VCode&& other) noexcept;
    
    // Appending subroutine: these are run in the order in which they are added.
    public:
        void enqueue_main_subr(std::string const& file_name, VSubr&& subr);
    
    // Core getters and setters:
    public:
        std::vector<VmExp>& exps() { return m_exps; };
        std::vector<VSubr>& subrs() { return m_subrs; };
        VmExp& operator[] (VmExpID exp_id) { return m_exps[exp_id]; }
        DefTable& def_tab() { return m_def_tab; }
        PlatformProcTable& pproc_tab() { return m_pproc_tab; }

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
        VmExpID new_vmx_frame(VmExpID fn_body_x, VmExpID post_ret_x);
        VmExpID new_vmx_argument(VmExpID x);
        VmExpID new_vmx_apply();
        VmExpID new_vmx_return(size_t n);
        VmExpID new_vmx_define(OBJECT var, VmExpID next);
        VmExpID new_vmx_box(ssize_t n, VmExpID next);
        VmExpID new_vmx_indirect(VmExpID next);
        VmExpID new_vmx_assign_local(size_t n, VmExpID next);
        VmExpID new_vmx_assign_free(size_t n, VmExpID next);
        VmExpID new_vmx_assign_global(size_t gn, VmExpID next);
        VmExpID new_vmx_shift(ssize_t n, ssize_t m, VmExpID x);
        VmExpID new_vmx_pinvoke(ssize_t arg_count, size_t platform_proc_idx, VmExpID x);

    // Globals:
    public:
        GDefID define_global(FLoc loc, IntStr name, OBJECT code = OBJECT::null, OBJECT init = OBJECT::null, std::string docstring = "");
        Definition const& global(GDefID gdef_id) const;
        Definition const* try_lookup_gdef_by_name(IntStr name) const;
        size_t count_globals() const { return m_def_tab.count_globals(); }

    // Platform procedures:
    public:
        PlatformProcID define_platform_proc(IntStr platform_proc_name, std::vector<IntStr> arg_names, PlatformProcCb callable_cb, std::string docstring, bool is_variadic);
        PlatformProcID lookup_platform_proc(IntStr platform_proc_name);
        PlatformProcCb platform_proc_cb(PlatformProcID id) { return m_pproc_tab.cb(id); }
        bool platform_proc_is_variadic(PlatformProcID id) { return m_pproc_tab.metadata(id).arity < 0; }
        ssize_t platform_proc_arity(PlatformProcID id) { return m_pproc_tab.metadata(id).arity; }
        size_t count_platform_procs() const { return m_pproc_tab.size(); }

    // dump:
    public:
        void dump(std::ostream& out) const;
        void print_all_exps(std::ostream& out) const;
        void print_one_exp(VmExpID exp_id, std::ostream& out) const;
        void print_all_files(std::ostream& out) const;
    };

}   // namespace ss
