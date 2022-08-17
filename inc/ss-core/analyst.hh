#pragma once

#include "ss-core/intern.hh"

namespace ss {

    class Analyst {
    protected:
        Analyst();
    public:
        IdCache const& id_cache() const { return g_id_cache(); }
    };

}