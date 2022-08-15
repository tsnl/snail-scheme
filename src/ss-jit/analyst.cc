#include "ss-jit/analyst.hh"

#include "ss-core/intern.hh"

namespace ss {

    Analyst::Analyst()
    :   m_id_cache({
            .quote = intern("quote"),
            .lambda = intern("lambda"),
            .if_ = intern("if"),
            .set = intern("set!"),
            .call_cc = intern("call/cc"),
            .define = intern("define"),
            .p_invoke = intern("p/invoke"),
            .begin = intern("begin"),
            .define_syntax = intern("define-syntax"),
            .ellipses = intern("..."),
            .underscore = intern("_")
        })
    {}

}