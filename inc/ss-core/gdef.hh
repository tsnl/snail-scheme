#pragma once

#include "ss-core/intern.hh"
#include "ss-core/object.hh"

namespace ss {

    using GDefID = size_t;

    class GDef {
    private:
        IntStr m_name;
        OBJECT m_code;
        std::string m_docstring;
    public:
        explicit GDef(IntStr name, OBJECT code, std::string docstring = "");
    public:
        IntStr name() { return m_name; }
        std::string docstring() { return m_docstring; }
    };

}