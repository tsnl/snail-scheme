#include "ss-jit/vglobals.hh"


namespace ss {

    void VGlobalTable::define_builtin_value(std::string name_str, OBJECT elt_obj) {
        OBJECT var_obj = OBJECT::make_interned_symbol(intern(std::move(name_str)));
        m_init_var_rib = cons(m_gc_tfe, var_obj, m_init_var_rib);
        m_init_val_rib = cons(m_gc_tfe, elt_obj, m_init_val_rib);
    }

    void VGlobalTable::define_builtin_fn(
        std::string name_str, 
        EXT_CallableCb callback, 
        std::vector<std::string> arg_names
    ) {
        // constructing a 'closure' object:
        OBJECT vars_list = OBJECT::make_null();
        for (size_t i = 0; i < arg_names.size(); i++) {
            vars_list = cons(m_gc_tfe, OBJECT::make_interned_symbol(intern(arg_names[i])), vars_list);
        }
        auto elt_obj_raw = new EXT_CallableObject(callback, m_init_val_rib, vars_list);
        auto elt_obj = OBJECT::make_generic_boxed(elt_obj_raw);

        // binding:
        define_builtin_value(std::move(name_str), elt_obj);
    }

}   // namespace ss
