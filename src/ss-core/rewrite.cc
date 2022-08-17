// cf https://www.gnu.org/software/guile/manual/html_node/Syntax-Case.html
// This module handles 2 jobs: resolving lexical scoping and macro expansion.
// It performs the following rewrites in this order:
// 1 To resolve scoping, reference symbols are replaced by the list
//   Treated as a pseudo-atom
//    `(reference ,(any 'local 'free 'global) ,def-id)
// 1 Similarly, 'set!' is replaced by the pseudo-atom
//    `(mutation ,(any 'local 'free 'global) ,def-id)
// 1 To avoid forwarding scopes and recomputing frees, lambdas are rewritten as
//   (lambda #'(args) '(bound-free-vars) #'body)
//   Note that bound-free-vars is an ordered list, and are not syntax objects
// 2 Macros are expanded recursively and completely, line-by-line.
//   This means we will not proceed to line N+1 until line N is fully expanded.
// 3 As an optimization, we rewrite
//   `((lambda ...) ...)`
//   into the body with formals substituted explicitly.
// We exclude the templates of `syntax-case` from this rewrite, only scoping on
// copy for instantiation.

#include <vector>
#include <stack>
#include <utility>
#include <optional>

#include "ss-core/analyst.hh"
#include "ss-core/common.hh"
#include "ss-core/rewrite.hh"
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

  class Scoper: public Analyst {
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
  private:
    OBJECT scope_const_expr_syntax(OBJECT expr_stx);
    OBJECT scope_pair_expr_syntax(OBJECT expr_stx);
    OBJECT scope_unwrapped_pair_syntax_data(FLoc loc, OBJECT expr_stx_data);
    OBJECT scope_unwrapped_list_syntax_data(FLoc loc, OBJECT expr_stx_data);
    OBJECT scope_unwrapped_list_syntax_data_for_lambda(FLoc loc, OBJECT head, OBJECT tail);
    OBJECT scope_unwrapped_list_syntax_data_for_if(FLoc loc, OBJECT head, OBJECT tail);
    OBJECT scope_unwrapped_list_syntax_data_for_set(FLoc loc, OBJECT head, OBJECT tail);
    OBJECT scope_unwrapped_list_syntax_data_for_call_cc(FLoc loc, OBJECT head, OBJECT tail);
    OBJECT scope_unwrapped_list_syntax_data_for_define(FLoc loc, OBJECT head, OBJECT tail);
    OBJECT scope_unwrapped_list_syntax_data_for_p_invoke(FLoc loc, OBJECT head, OBJECT tail);
    OBJECT scope_unwrapped_list_syntax_data_for_begin(FLoc loc, OBJECT head, OBJECT tail);
    OBJECT scope_unwrapped_list_syntax_data_for_apply(FLoc loc, OBJECT head, OBJECT tail);
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
    auto expr_stx_p = static_cast<SyntaxObject*>(expr_stx.as_ptr());
    OBJECT data = expr_stx_p->data();
    if (data.is_interned_symbol()) {
      auto [rel_var_scope, def_id] = refer(data);
      IntStr rel_var_scope_sym = [](RelVarScope rel_var_scope) -> IntStr {
        switch (rel_var_scope) {
          case RelVarScope::Local: return g_id_cache().local;
          case RelVarScope::Free: return g_id_cache().free;
          case RelVarScope::Global: return g_id_cache().global;
        };
        error("Unknown rel_var_scope");
        throw SsiError();
      }(rel_var_scope);
      return OBJECT::make_syntax(
        &m_gc_tfe,
        list(
          &m_gc_tfe, 
          OBJECT::make_interned_symbol(g_id_cache().reference),
          OBJECT::make_interned_symbol(rel_var_scope_sym),
          OBJECT::make_integer(def_id)
        ),
        expr_stx_p->loc()
      );
    }
    if (data.is_pair()) {
      auto new_data = scope_unwrapped_pair_syntax_data(expr_stx_p->loc(), data);
      return OBJECT::make_syntax(&m_gc_tfe, new_data, expr_stx_p->loc());
    }
    return scope_const_expr_syntax(expr_stx);
  }
  OBJECT Scoper::scope_const_expr_syntax(OBJECT expr_stx) {
    assert(expr_stx.is_syntax());
    error("not-implemented: scope_const_expr_syntax");
    throw SsiError();
  }
  OBJECT Scoper::scope_unwrapped_pair_syntax_data(FLoc loc, OBJECT expr_stx_data) {
    auto obj = static_cast<PairObject*>(expr_stx_data.as_ptr());

    OBJECT car_syntax = obj->car();
    OBJECT cdr = obj->cdr();

    if (cdr.is_list()) {
      return scope_unwrapped_list_syntax_data(loc, expr_stx_data);
    } else {
      return cons(
        &m_gc_tfe,
        scope_expr_syntax(car_syntax),
        scope_expr_syntax(cdr)
      );
    }
  }
  OBJECT Scoper::scope_unwrapped_list_syntax_data_for_lambda(FLoc loc, OBJECT head, OBJECT tail) {
    auto args = extract_args<2>(tail);
    auto vars_syntax = args[0];
    auto body_syntax = args[1];

    assert(vars_syntax.is_syntax());
    auto vars_syntax_p = static_cast<SyntaxObject*>(vars_syntax.as_ptr());

    assert(body_syntax.is_syntax());
    auto body_syntax_p = static_cast<PairObject*>(body_syntax.as_ptr());

    OBJECT vars_syntax_d = vars_syntax_p->data();

    OBJECT vars = vars_syntax_p->to_datum(&m_gc_tfe);
    check_vars_list_else_throw(vars);

    push_scope();
    {
      for (OBJECT args = vars_syntax_d; !args.is_null(); args = cdr(args)) {
        OBJECT arg = car(args);
        assert(arg.is_syntax());
        auto arg_p = static_cast<SyntaxObject*>(arg.as_ptr());
        OBJECT arg_name = arg_p->data();
        assert(arg_name.is_interned_symbol());
        define_local(arg_p->loc(), arg_name.as_interned_symbol());
      }
      scope_expr_syntax(body_syntax);
    }
    auto free_vars_vec = pop_scope();
    OBJECT free_vars = OBJECT::null;
    for (IntStr it: free_vars_vec) {
      free_vars = cons(&m_gc_tfe, OBJECT::make_interned_symbol(it), free_vars);
    }

    // (lambda #'(formal-vars) '(bound-vars) #'body)
    return list(
      &m_gc_tfe, 
      head,           // lambda, but a syntax object
      vars_syntax,
      free_vars,      // note: not syntax objects since synthetic
      body_syntax
    );
  }
  OBJECT Scoper::scope_unwrapped_list_syntax_data_for_if(FLoc loc, OBJECT head, OBJECT tail) {
    auto args = extract_args<3>(tail);
    auto cond = args[0];
    auto then = args[1];
    auto else_ = args[2];
    return list(
      &m_gc_tfe,
      head,   // if, but a syntax object
      scope_expr_syntax(cond),
      scope_expr_syntax(then),
      scope_expr_syntax(else_)
    );
  }
  OBJECT Scoper::scope_unwrapped_list_syntax_data_for_set(FLoc loc, OBJECT head, OBJECT tail) {
    // (mutation ,(any 'local 'free 'global) ,def-id)
    error("not-implemented: scope_unwrapped_list_syntax_data_for_set");
    throw SsiError();
  }
  OBJECT Scoper::scope_unwrapped_list_syntax_data_for_call_cc(FLoc loc, OBJECT head, OBJECT tail) {
    error("not-implemented: scope_unwrapped_list_syntax_data_for_call_cc");
    throw SsiError();
  }
  OBJECT Scoper::scope_unwrapped_list_syntax_data_for_define(FLoc loc, OBJECT head, OBJECT tail) {
    error("not-implemented: scope_unwrapped_list_syntax_data_for_define");
    throw SsiError();
  }
  OBJECT Scoper::scope_unwrapped_list_syntax_data_for_p_invoke(FLoc loc, OBJECT head, OBJECT tail) {
    error("not-implemented: scope_unwrapped_list_syntax_data_for_p_invoke");
    throw SsiError();
  }
  OBJECT Scoper::scope_unwrapped_list_syntax_data_for_begin(FLoc loc, OBJECT head, OBJECT tail) {
    error("not-implemented: scope_unwrapped_list_syntax_data_for_begin");
    throw SsiError();
  }
  OBJECT Scoper::scope_unwrapped_list_syntax_data_for_apply(FLoc loc, OBJECT head, OBJECT tail) {
    error("not-implemented: scope_unwrapped_list_syntax_data_for_apply");
    throw SsiError();
  }
  OBJECT Scoper::scope_unwrapped_list_syntax_data(FLoc loc, OBJECT expr_stx_data) {
    auto obj = static_cast<PairObject*>(expr_stx_data.as_ptr());

    if (!obj->car().is_syntax()) {
      // synthetic form
      assert(obj->car().is_interned_symbol());
      if (obj->car().as_interned_symbol() == g_id_cache().reference) {
        return expr_stx_data;
      }
      error("compiler-error: unknown synthetic syntax atom");
      throw SsiError();
    }

    OBJECT head_syntax = obj->car();
    OBJECT tail_syntax = obj->cdr();
    
    assert(tail_syntax.is_list());

    auto head_syntax_p = static_cast<SyntaxObject*>(head_syntax.as_ptr());
    auto tail_syntax_p = static_cast<SyntaxObject*>(head_syntax.as_ptr());

    OBJECT head = head_syntax_p->data();
    OBJECT tail = tail_syntax_p->data();

    if (head.is_interned_symbol()) {
      auto keyword_symbol_id = head.as_interned_symbol();

      // lambda
      if (keyword_symbol_id == g_id_cache().lambda) {
        return scope_unwrapped_list_syntax_data_for_lambda(loc, head, tail);
      }

      // if
      if (keyword_symbol_id == g_id_cache().if_) {
        return scope_unwrapped_list_syntax_data_for_if(loc, head, tail);
      }

      // set!
      if (keyword_symbol_id == g_id_cache().set) {
        return scope_unwrapped_list_syntax_data_for_set(loc, head, tail);
      }

      // call/cc
      if (keyword_symbol_id == g_id_cache().call_cc) {
        return scope_unwrapped_list_syntax_data_for_call_cc(loc, head, tail);
      }

      // define
      if (keyword_symbol_id == g_id_cache().define) {
        return scope_unwrapped_list_syntax_data_for_define(loc, head, tail);
      }

      // p/invoke
      if (keyword_symbol_id == g_id_cache().p_invoke) {
        return scope_unwrapped_list_syntax_data_for_p_invoke(loc, head, tail);
      }

      // begin
      if (keyword_symbol_id == g_id_cache().begin) {
        return scope_unwrapped_list_syntax_data_for_begin(loc, head, tail);
      }

      // quote
      if (keyword_symbol_id == g_id_cache().quote) {
        return expr_stx_data;
      }

      // fallthrough
    }

    return scope_unwrapped_list_syntax_data_for_apply(loc, head, tail);
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