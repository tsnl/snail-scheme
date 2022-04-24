#pragma once

#include "ss-core/gc.hh"
#include "ss-jit/vrom.hh"

namespace ss {

    class OBJECT;

    class Compiler {
    private:
        VRom m_rom;
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
        VScript compile_script(std::string str, std::vector<OBJECT> line_code_objects, OBJECT init_var_rib);
        ScopedVmProgram translate_single_line_code_obj(OBJECT line_code_obj, OBJECT var_e);
        ScopedVmExp translate_code_obj(OBJECT obj, VmExpID next, OBJECT var_e);
        ScopedVmExp translate_code_obj__pair_list(PairObject* obj, VmExpID next, OBJECT var_e);
        bool is_tail_vmx(VmExpID vmx_id);

    private:
        OBJECT compile_lookup(OBJECT symbol, OBJECT var_env_raw);
        void check_vars_list_else_throw(OBJECT vars);
        OBJECT compile_extend(OBJECT e, OBJECT vars);

    public:
        inline VRom& rom() { return m_rom; }
    };

}
