#pragma once

#include <utility>

#include "robin_hood.h"

#include "ss-core/gc.hh"
#include "ss-jit/vcode.hh"

namespace ss {

    class OBJECT;

    enum class RelVarScope { Local, Free, Global };

    class Compiler {
    private:
        VCode m_code;
        GcThreadFrontEnd& m_gc_tfe;
        
        const struct {
            IntStr const quote;
            IntStr const lambda;
            IntStr const if_;
            IntStr const set;
            IntStr const call_cc;
            IntStr const define;
            IntStr const begin;
        } m_builtin_intstr_id_cache;

    public:
        explicit Compiler(GcThreadFrontEnd& gc_tfe);
    
    public:
        VScript compile_script(std::string str, std::vector<OBJECT> line_code_objects);
        VmProgram compile_line(OBJECT line_code_obj, OBJECT var_e);
        VmExpID compile_exp(OBJECT obj, VmExpID next, OBJECT var_e);
        VmExpID compile_pair_list_exp(PairObject* obj, VmExpID next, OBJECT var_e);
        VmExpID compile_refer(OBJECT x, OBJECT e, VmExpID next);
        bool is_tail_vmx(VmExpID vmx_id);

    private:
        std::pair<RelVarScope, size_t> compile_lookup(OBJECT symbol, OBJECT var_env_raw);
        void check_vars_list_else_throw(OBJECT vars);
        OBJECT compile_extend(OBJECT e, OBJECT vars);
        VmExpID collect_free(OBJECT vars, OBJECT e, VmExpID next);

    // Scheme set functions:
    private:
        bool is_set_member(OBJECT x, OBJECT s);
        OBJECT set_cons(OBJECT x, OBJECT s);
        OBJECT set_union(OBJECT s1, OBJECT s2);
        OBJECT set_minus(OBJECT s1, OBJECT s2);
        OBJECT set_intersect(OBJECT s1, OBJECT s2);

    // Find-free:
    private:
        OBJECT find_free(OBJECT x, OBJECT b);

    // Code:
    public:
        inline VCode& code() { return m_code; }
        inline VCode const& code() const { return m_code; }
    };

}
