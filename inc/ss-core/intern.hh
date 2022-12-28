#pragma once

#include <cstddef>
#include <string>

namespace ss {

    using IntStr = size_t;

    IntStr intern(std::string s);
    std::string const& interned_string(IntStr int_str);

    struct IdCache {
        IntStr const quote;
        IntStr const lambda;
        IntStr const if_;
        IntStr const set;
        IntStr const call_cc;
        IntStr const define;
        IntStr const p_invoke;
        IntStr const begin;
        IntStr const define_syntax;
        IntStr const ellipses;
        IntStr const underscore;
        IntStr const reference;
        IntStr const local;
        IntStr const free;
        IntStr const global;
        IntStr const mutation;
        IntStr const expanded_lambda;
        IntStr const expanded_define;
        IntStr const expanded_p_invoke;
    };
    IdCache const& g_id_cache();

}   // namespace ss
