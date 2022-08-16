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

  class GDefTable {
  private:
    std::vector<GDef> m_gdef_vec;
    UnstableHashMap<IntStr, GDefID> m_gdef_id_symtab;

  public:
    GDefID define(IntStr name, OBJECT code=OBJECT::null, OBJECT init=OBJECT::null, std::string docstring="");
  public:
    inline GDef const& lookup(IntStr name) { return get(m_gdef_id_symtab[name]); }
    inline GDef const& get(GDefID gdef_id) const { return m_gdef_vec[gdef_id]; }
    inline size_t count() const { return m_gdef_vec.size(); }
  };

}