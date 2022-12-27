#pragma once

#include <vector>
#include <optional>
#include <utility>

#include "ss-core/common.hh"
#include "ss-core/intern.hh"
#include "ss-core/gc.hh"
#include "ss-core/pinvoke.hh"
#include "ss-core/defn.hh"
#include "ss-core/vcode.hh"
#include "ss-core/analyst.hh"
#include "ss-core/expander.hh"

namespace ss {

    class OBJECT;

    class Compiler: public Analyst {
    private:
        VCode* m_code;
        GcThreadFrontEnd& m_gc_tfe;
        OBJECT m_gdef_set;
        
    public:
        explicit Compiler(GcThreadFrontEnd& gc_tfe);
    
    public:
        VSubr compile_expr(std::string subr_name, OBJECT line_code_object);
        VSubr compile_subr(std::string subr_name, std::vector<OBJECT> line_code_objects);
        VmProgram compile_line(OBJECT line_code_obj);
        VmExpID compile_exp(OBJECT x, VmExpID next);
        VmExpID compile_list_exp(PairObject* x, VmExpID next);
        VmExpID refer_nonlocal(OBJECT x, VmExpID next);
        bool is_tail_vmx(VmExpID vmx_id);

    // Utility builders:
    private:
        VmExpID collect_free(OBJECT vars, VmExpID next);
        VmExpID make_boxes(OBJECT vars, VmExpID next);

    // Globals:
    public:
        GDefID define_global(FLoc loc, IntStr name, OBJECT code = OBJECT::null, OBJECT init = OBJECT::null, std::string docstring = "");
        Definition const& lookup_gdef(GDefID gdef_id) const;
        Definition const* try_lookup_gdef_by_name(IntStr name) const;
        size_t count_globals() const { return m_code->count_globals(); }
        void initialize_platform_globals(std::vector<OBJECT>& global_vals);

    // Platform procs:
    public:
        PlatformProcID define_platform_proc(
            IntStr platform_proc_name, 
            std::vector<std::string> arg_names, 
            PlatformProcCb callable_cb, 
            std::string docstring, 
            bool is_variadic = false
        );
        PlatformProcID lookup_platform_proc(IntStr name);

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
