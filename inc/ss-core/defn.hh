#pragma once

#include <optional>
#include "ss-core/intern.hh"
#include "ss-core/object.hh"
#include "ss-core/feedback.hh"

namespace ss {

  using GDefID = size_t;
  using LDefID = size_t;

  class Definition {
  private:
    IntStr m_name;
    OBJECT m_code;
    OBJECT m_init;
    std::string m_docstring;
    FLoc m_loc;
    bool m_is_mutated;
  public:
    explicit Definition(FLoc loc, IntStr name, OBJECT code, OBJECT init, std::string docstring = "");
  public:
    void mark_as_mutated();
  public:
    IntStr name() const { return m_name; }
    std::string docstring() const { return m_docstring; }
    OBJECT code() const { return m_code; }
    OBJECT init() const { return m_init; }
    FLoc loc() const { return m_loc; }
    bool is_mutated() const { return m_is_mutated; }
  };

  class DefTable {
  private:
    std::vector<Definition> m_globals_vec;
    std::vector<Definition> m_locals_vec;
    UnstableHashMap<IntStr, GDefID> m_globals_id_symtab;
  public:
    void mark_global_defn_mutated(GDefID def_id);
    void mark_local_defn_mutated(LDefID def_id);
  public:
    GDefID define_global(FLoc loc, IntStr name, OBJECT code=OBJECT::null, OBJECT init=OBJECT::null, std::string docstring="");
    LDefID define_local(FLoc loc, IntStr name, OBJECT code=OBJECT::null, OBJECT init=OBJECT::null, std::string docstring="");
    std::optional<GDefID> lookup_global_id(IntStr name) const;
  public:
    inline Definition const& global(GDefID gdef_id) const { return m_globals_vec[gdef_id]; }
    inline Definition const& local(LDefID ldef_id) const { return m_locals_vec[ldef_id]; }
  public:
    inline size_t count_globals() const { return m_globals_vec.size(); }
  };

}
