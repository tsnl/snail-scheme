// cf https://www.gnu.org/software/guile/manual/html_node/Syntax-Case.html
// This module handles 2 jobs: resolving lexical scoping and macro expansion.
// To resolve scoping, reference symbols are replaced by the list
// `(reference ,(any 'local 'free 'global) ,def-id)
// We exclude the templates of `syntax-case` from this rewrite, only scoping on
// copy for instantiation.

#include <vector>
#include <stack>
#include <utility>
#include <optional>

#include "ss-core/common.hh"
#include "ss-core/expander.hh"
#include "ss-core/defn.hh"
#include "ss-core/pinvoke.hh"
#include "ss-core/gc.hh"
#include "ss-core/feedback.hh"

//
// Impl: common utility
//

// abbreviations:
namespace ss {
  using GCTFE = GcThreadFrontEnd;
}

// OrderedSymbolSet: flat vector-based ordered sets
namespace ss {

  class OrderedSymbolSet {
  private:
    using Container = std::vector<IntStr>;
  private:
    Container m_elements;
  public:
    OrderedSymbolSet() = default;
    OrderedSymbolSet(OrderedSymbolSet const& other) = default;
    OrderedSymbolSet(OrderedSymbolSet&& other) = default;
  public:
    OrderedSymbolSet(std::vector<IntStr> names);
  public:
    void add(IntStr element);
    std::optional<size_t> idx(IntStr element) const;
    bool contains(IntStr element) const { return idx(element).has_value(); }
  public:
    void reserve(size_t count) { m_elements.reserve(count); }
    std::vector<IntStr> const& vec() const { return m_elements; }
    Container::const_iterator begin() const { return m_elements.begin(); }
    Container::const_iterator end() const { return m_elements.end(); }
    size_t size() const { return m_elements.size(); }
    void swap(OrderedSymbolSet other) { m_elements.swap(other.m_elements); }
  public:
    IntStr operator[](size_t idx) const { return m_elements[idx]; }
  public:
    OrderedSymbolSet operator|(OrderedSymbolSet const& other) const;
    OrderedSymbolSet operator&(OrderedSymbolSet const& other) const;
  };

  OrderedSymbolSet::OrderedSymbolSet(std::vector<IntStr> names) {
    for (auto it: names) {
      add(it);
    }
  }

  void OrderedSymbolSet::add(IntStr element) {
    if (!contains(element)) {
      m_elements.push_back(element);
    }
  }
  std::optional<size_t> OrderedSymbolSet::idx(IntStr element) const {
    for (size_t i = 0; i < m_elements.size(); i++) {
      if (m_elements[i] == element) {
        return {i};
      }
    }
    return {};
  }

  OrderedSymbolSet OrderedSymbolSet::operator|(OrderedSymbolSet const& other) const {
    OrderedSymbolSet result{*this};
    result.reserve(size() + other.size());
    for (IntStr other_elem: other) {
      result.add(other_elem);
    }
    return result;
  }
  OrderedSymbolSet OrderedSymbolSet::operator&(OrderedSymbolSet const& other) const {
    OrderedSymbolSet result;
    for (IntStr other_elem: other) {
      if (contains(other_elem)) {
        result.add(other_elem);
      }
    }
    return result;
  }
}

//
// Impl: Scope
//

namespace ss {
  struct Scope {
  public:
    OrderedSymbolSet locals;
    std::vector<LDefID> local_defs;
    OrderedSymbolSet inuse_nonlocals;
    std::vector<LDefID> inuse_nonlocal_defs;
  public:
    Scope()
    : locals(),
      local_defs(),
      inuse_nonlocals(),
      inuse_nonlocal_defs()
    {
      assert(locals.size() == local_defs.size());
    }
  };
}

//
// Impl: scoper
//

namespace ss {

  class Scoper {
  private:
    GCTFE& m_gc_tfe;
    DefTable& m_def_tab; 
    PlatformProcTable& m_pproc_tab;
    std::vector<Scope> m_scope_stack;
  public:
    inline Scoper(GCTFE& gc_tfe, DefTable& gdef_tab, PlatformProcTable& pproc_tab);
  public:
    // pushes a fresh scope containing the given symbols
    void push_scope();

    // returns a unique list of free variables referenced
    std::vector<LDefID> pop_scope();

    // defines a local variable in the current scope
    LDefID define_local(FLoc loc, IntStr name);
    
    // looks up a variable, returning the scope it was found in and an ID
    // - if local, then (RelVarScope::Local, LDefID)
    // - if nonlocal, then (RelVarScope::Free, LDefID) 
    // - if global, then (RelVarScope::Global, GDefID)
    std::pair<RelVarScope, size_t> refer(OBJECT symbol);

  public:
    OBJECT scope_expr_syntax(OBJECT expr_stx);
  };
  
  inline Scoper::Scoper(GCTFE& gc_tfe, DefTable& def_tab, PlatformProcTable& pproc_tab)
  : m_gc_tfe(gc_tfe),
    m_def_tab(def_tab),
    m_pproc_tab(pproc_tab),
    m_scope_stack()
  {
    m_scope_stack.reserve(256);
  }
  
  void Scoper::push_scope() {
    m_scope_stack.emplace_back();
  }
  std::vector<LDefID> Scoper::pop_scope() {
    auto res = std::move(m_scope_stack.back().inuse_nonlocal_defs);
    m_scope_stack.pop_back();
    return res;
  }

  LDefID Scoper::define_local(FLoc loc, IntStr name) {
    assert(!m_scope_stack.empty());
    if (m_scope_stack.back().locals.contains(name)) {
      std::stringstream s;
      s << "Local variable re-defined in scope: " << interned_string(name) << std::endl
        << "see: " << loc.as_text();
      error(s.str());
      throw SsiError();
    } else {
      LDefID ldef_id = m_def_tab.define_local(loc, name);
      m_scope_stack.back().locals.add(name);
      m_scope_stack.back().local_defs.push_back(ldef_id);
      return ldef_id;
    }
  }
  
  inline std::pair<RelVarScope, size_t> Scoper::refer(OBJECT symbol) {
    // compile-time type-checks
    if (!symbol.is_interned_symbol()) {
      error("broken query symbol in refer: expected symbol");
      throw SsiError();
    }
    
    IntStr sym = symbol.as_interned_symbol();
    Scope& top = m_scope_stack.back();

    // checking 'locals'
    {
      auto opt_idx = top.locals.idx(sym);
      if (opt_idx.has_value()) {
        LDefID ldef_id = top.local_defs[opt_idx.value()];
        return {RelVarScope::Local, ldef_id};
      }
    }

    // checking 'free', trying to get index:
    {
      auto opt_cached_idx = top.inuse_nonlocals.idx(sym);
      if (opt_cached_idx.has_value()) {
        auto cached_idx = opt_cached_idx.value();
        LDefID ldef_id = top.inuse_nonlocal_defs[cached_idx];
        return {RelVarScope::Free, ldef_id};
      } else {
        // must check whole scope stack, and if found, must insert into 'inuse' table
        my_ssize_t found_idx = -1;
        LDefID found_ldef_id = static_cast<LDefID>(-1);
        for (my_ssize_t i = m_scope_stack.size()-2; i >= 0; i--) {
          auto opt_idx = m_scope_stack[i].locals.idx(sym);
          if (opt_idx.has_value()) {
            found_idx = opt_idx.value();
            found_ldef_id = m_scope_stack[i].inuse_nonlocal_defs[found_idx];
            break;
          }
        }
        if (found_idx >= 0) {
          // insert into 'inuse' table, then return
          top.inuse_nonlocals.add(sym);
          top.inuse_nonlocal_defs.push_back(found_ldef_id);
          return {RelVarScope::Free, found_ldef_id};
        }
      }
    }
    
    // checking globals
    {
      auto opt_gdef_id = m_def_tab.lookup_global_id(symbol.as_interned_symbol());
      if (opt_gdef_id.has_value()) {
        return {RelVarScope::Global, opt_gdef_id.value()};
      }
    }
    
    // lookup failed:
    {
      std::stringstream ss;
      ss << "Lookup failed: symbol used but not defined: " << symbol;
      error(ss.str());
      throw SsiError();
    }
  }

  OBJECT Scoper::scope_expr_syntax(OBJECT expr_stx) {
    assert(expr_stx.is_syntax());

  }
}

//
// Impl: macroexpand
//

namespace ss {
  OBJECT macroexpand_syntax_impl(OBJECT expr_stx) {
    OBJECT env = OBJECT::null;
    
    // TODO: scope this expression, excluding templates of syntax-case.
    // If macro applications are detected, they are expanded fully before 
    // scoping continues.
    // Thus, we can use the same pass to perform scoping, full macro expansion.

    // for each top-level statement, first expand fully using bound transformers,
    // then try binding a new transformer if needed.
    // - fully expand => recursively expand upto fixed point
    //   - on each expansion,
    //     - replace template with actual syntax objects => replacement
    //     - scope the replacement, expanding macros as found.
    //     - replace macro invocation with replacement


    return expr_stx;
  }
}

//
// Interface:
//

namespace ss {
  OBJECT macroexpand_syntax(OBJECT expr_stx) {
    return macroexpand_syntax_impl(expr_stx);
  }
}