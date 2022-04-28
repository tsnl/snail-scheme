#pragma once

#include <vector>
#include <optional>
#include <utility>

#include "ss-core/common.hh"
#include "ss-core/intern.hh"
#include "ss-core/gc.hh"
#include "ss-core/gdef.hh"
#include "ss-jit/vcode.hh"
#include "ss-jit/analyst.hh"

namespace ss {

    class OBJECT;

    enum class RelVarScope { Local, Free, Global };

    class Compiler: public Analyst {
    private:
        VCode* m_code;
        GcThreadFrontEnd& m_gc_tfe;
        
    public:
        explicit Compiler(GcThreadFrontEnd& gc_tfe);
    
    public:
        VSubr compile_subroutine(std::string str, std::vector<OBJECT> line_code_objects);
        VmProgram compile_line(OBJECT line_code_obj, OBJECT var_e);
        VmExpID compile_exp(OBJECT x, VmExpID next, OBJECT e, OBJECT s);
        VmExpID compile_pair_list_exp(PairObject* x, VmExpID next, OBJECT e, OBJECT s);
        VmExpID compile_refer(OBJECT x, OBJECT e, VmExpID next);
        bool is_tail_vmx(VmExpID vmx_id);

    private:
        std::pair<RelVarScope, size_t> compile_lookup(OBJECT symbol, OBJECT var_env_raw);
        void check_vars_list_else_throw(OBJECT vars);
        OBJECT compile_extend(OBJECT e, OBJECT vars);
        
    // Utility builders:
    private:
        VmExpID collect_free(OBJECT vars, OBJECT e, VmExpID next);
        VmExpID make_boxes(OBJECT sets, OBJECT vars, VmExpID next);

    // Globals:
    public:
        GDefID define_global(IntStr name, OBJECT code = OBJECT::null, std::string docstring = "");
        GDef const& lookup_gdef(GDefID gdef_id) const;
        GDef const* try_lookup_gdef_by_name(IntStr name) const;
        size_t count_globals() const { return m_code->count_globals(); }

    // Scheme set functions:
    private:
        bool is_set_member(OBJECT x, OBJECT s);
        OBJECT set_cons(OBJECT x, OBJECT s);
        OBJECT set_union(OBJECT s1, OBJECT s2);
        OBJECT set_minus(OBJECT s1, OBJECT s2);
        OBJECT set_intersect(OBJECT s1, OBJECT s2);

    // Find-free: finds all free variables in use
    //   b => 'bound', the set of bound variable symbol objects, implemented using 'Scheme set'
    private:
        OBJECT find_free(OBJECT x, OBJECT b);

    // Find-sets: finds all occurrences of `set!` that apply to free variables.
    private:
        OBJECT find_sets(OBJECT x, OBJECT v);

    // Code:
    public:
        inline VCode* code() { return m_code; }
        inline VCode const* code() const { return m_code; }
    };

}
