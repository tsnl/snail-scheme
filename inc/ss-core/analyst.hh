#pragma once

#include "ss-core/file-loc.hh"
#include "ss-core/intern.hh"
#include "ss-core/object.hh"

namespace ss {

    class Analyst {
    protected:
        Analyst();
    public:
        IdCache const& id_cache() const { return g_id_cache(); }
        void check_vars_list_else_throw(FLoc loc, OBJECT vars);
    };

}