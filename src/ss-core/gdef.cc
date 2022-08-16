#include "ss-core/gdef.hh"

namespace ss {

  GDef::GDef(IntStr name, OBJECT code, OBJECT init, std::string docstring)
  : m_name(name),
    m_code(code),
    m_init(init),
    m_docstring(std::move(docstring))
  {}

  GDefID GDefTable::define(
    IntStr name, 
    OBJECT code=OBJECT::null, OBJECT init=OBJECT::null, 
    std::string docstring=""
  ) {
    GDefID new_gdef_id = m_gdef_vec.size();
    m_gdef_vec.emplace_back(name, code, init, std::move(docstring));
    m_gdef_id_symtab[name] = new_gdef_id;
    return new_gdef_id;
  }

}