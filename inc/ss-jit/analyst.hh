#pragma once

#include "ss-core/intern.hh"

namespace ss {

    class Analyst {
    protected:
        const struct {
            IntStr const quote;
            IntStr const lambda;
            IntStr const if_;
            IntStr const set;
            IntStr const call_cc;
            IntStr const define;
            IntStr const begin;
            IntStr const define_syntax;
        } m_id_cache;
    protected:
        Analyst();
    };

}