/// Efficient O(1) name-based (hash-map) OR ID-based (LUT) storage of
/// global variables.
/// - SVEnv determines size of table and layout, determined at compile-time.
///   Behavior identical to `init_var_rib`.
/// - VEnv is just a vector table of objects.
///   Behavior identical to `init_val_rib`.

#pragma once

#include <deque>

#include "robin_hood.h"

#include "ss-core/object.hh"
#include "ss-core/gc.hh"

namespace ss {

    using GDefID = size_t;

    // TODO: implement me

    class VGlobalTable {
    private:
        OBJECT m_init_var_rib;
        OBJECT m_init_val_rib;
        GcThreadFrontEnd* m_gc_tfe;
    public:
        VGlobalTable(GcThreadFrontEnd* gc_tfe);
    public:
        void define_builtin_value(std::string name_str, OBJECT elt_obj);
        void define_builtin_fn(std::string name_str, EXT_CallableCb callback, std::vector<std::string> arg_names);
    };
}