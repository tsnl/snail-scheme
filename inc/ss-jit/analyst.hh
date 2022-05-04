#pragma once

#include "ss-core/intern.hh"

namespace ss {

    class Analyst {
    public:
        struct IdCache {
            IntStr const quote;
            IntStr const lambda;
            IntStr const if_;
            IntStr const set;
            IntStr const call_cc;
            IntStr const define;
            IntStr const begin;
            IntStr const define_syntax;
            IntStr const ellipses;
            IntStr const underscore;
        };
    protected:
        IdCache const m_id_cache;
    protected:
        Analyst();
    public:
        IdCache const& id_cache() const { return m_id_cache; }
    };

}