#include "ss-core/defn.hh"

namespace ss {

  Definition::Definition(FLoc loc, IntStr name, OBJECT code, OBJECT init, std::string docstring)
  : m_name(name),
    m_code(code),
    m_init(init),
    m_docstring(std::move(docstring)),
    m_loc(loc),
    m_is_mutated(false)
  {}

  void Definition::mark_as_mutated() {
    m_is_mutated = true;
  }

  void DefTable::mark_global_defn_mutated(GDefID def_id) {
    m_globals_vec[def_id].mark_as_mutated();
  }
  void DefTable::mark_local_defn_mutated(LDefID def_id) {
    m_locals_vec[def_id].mark_as_mutated();
  }

  GDefID DefTable::define_global(
    FLoc loc, IntStr name, 
    OBJECT code, OBJECT init, 
    std::string docstring
  ) {
    GDefID new_gdef_id = m_globals_vec.size();
    m_globals_vec.emplace_back(loc, name, code, init, std::move(docstring));
    m_globals_id_symtab[name] = new_gdef_id;
    return new_gdef_id;
  }

  LDefID DefTable::define_local(
    FLoc loc, IntStr name, 
    OBJECT code, OBJECT init, 
    std::string docstring
  ) {
    LDefID new_ldef_id = m_locals_vec.size();
    m_locals_vec.emplace_back(loc, name, code, init, std::move(docstring));
    return new_ldef_id;
  }

  std::optional<GDefID> DefTable::lookup_global_id(IntStr name) const { 
    auto found_it = m_globals_id_symtab.find(name);
    if (found_it != m_globals_id_symtab.end()) {
      return {found_it->second};
    } else {
      std::optional<GDefID> res = {};
      return res;
    }
  }
}