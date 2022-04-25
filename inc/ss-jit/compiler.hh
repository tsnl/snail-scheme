#pragma once

#include <utility>
#include "robin_hood.h"

#include "ss-core/gc.hh"
#include "ss-jit/vrom.hh"

namespace ss {

    class OBJECT;

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
        bool is_tail_vmx(VmExpID vmx_id);

    private:
        std::pair<size_t, size_t> compile_lookup(OBJECT symbol, OBJECT var_env_raw);
        void check_vars_list_else_throw(OBJECT vars);
        OBJECT compile_extend(OBJECT e, OBJECT vars);

    public:
        inline VCode& code() { return m_code; }
    };

}
