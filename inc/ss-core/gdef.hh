#pragma once

#include "ss-core/intern.hh"
#include "ss-core/object.hh"

namespace ss {

    using GDefID = size_t;

    class GDef {
    private:
        IntStr m_name;
        OBJECT m_code;
        OBJECT m_init;
        std::string m_docstring;
    public:
        explicit GDef(IntStr name, OBJECT code, OBJECT init, std::string docstring = "");
    public:
        IntStr name() const { return m_name; }
        std::string docstring() const { return m_docstring; }
        OBJECT code() const { return m_code; }
        OBJECT init() const { return m_init; }
    };

}