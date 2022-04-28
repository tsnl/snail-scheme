#include "ss-core/gdef.hh"

namespace ss {

    GDef::GDef(IntStr name, OBJECT code, std::string docstring)
    :   m_name(name),
        m_code(code),
        m_docstring(std::move(docstring))
    {}

}