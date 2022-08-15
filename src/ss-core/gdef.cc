#include "ss-core/gdef.hh"

namespace ss {

    GDef::GDef(IntStr name, OBJECT code, OBJECT init, std::string docstring)
    :   m_name(name),
        m_code(code),
        m_init(init),
        m_docstring(std::move(docstring))
    {}

}