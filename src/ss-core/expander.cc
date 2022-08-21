// cf https://www.gnu.org/software/guile/manual/html_node/Syntax-Case.html
// This module handles 2 jobs: resolving lexical scoping and macro expansion.
// Rather than an iterative approach, we fully, recursively expand each line
// before moving to the next one.
// It performs the following rewrites in this order:
// 1 To resolve scoping, reference symbols are replaced by the list
//   Treated as a pseudo-atom
//    `(reference ,rel-var-scope ,def-id)
// 1 Similarly, 'set!' is replaced by the pseudo-atom
//    `(mutation ,rel-var-scope ,def-id ,scoped-initializer-stx)
// 1 To avoid forwarding scopes and recomputing frees, lambdas are rewritten as
//   (lambda #'(args) '(bound-free-vars) #'body)
//   Note that bound-free-vars is an ordered list of pairs, and are not syntax objects
//   Each bound-free-var element is a pair (ldef-id . use-is-mut) (cf Nonlocal)
//   Each args element is an ldef-id integer wrapped in a SyntaxObject; we replace ID by int.
// 1 Similarly, 'define' is replaced 
//    (define ,rel-var-scope #,def-id #,scoped-initializer-stx)
// 1 Similarly, 'p/invoke' is replaced
//    (p/invoke #,pproc-id #,args ...)
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

// RelVarScope as sym
namespace ss {
  IntStr rel_var_scope_to_sym(RelVarScope rel_var_scope) {
    switch (rel_var_scope) {
      case RelVarScope::Local: return g_id_cache().local;
      case RelVarScope::Free: return g_id_cache().free;
      case RelVarScope::Global: return g_id_cache().global;
    }
    error("Unknown rel_var_scope");
    throw SsiError();
  }
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
  
  struct Nonlocal {
    LDefID ldef_id;
    bool use_is_mut;
    Nonlocal(LDefID ldef_id, bool use_is_mut): ldef_id(ldef_id), use_is_mut(use_is_mut) {}
  };

  struct Scope {
  public:
    OrderedSymbolSet locals;
    std::vector<LDefID> local_defs;
    OrderedSymbolSet inuse_nonlocals;
    std::vector<Nonlocal> inuse_nonlocal_defs;
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
// Impl: expander
//

namespace ss {

  class Scoper: public Analyst {
  private:
    GCTFE& m_gc_tfe;
    DefTable& m_def_tab; 
    PlatformProcTable& m_pproc_tab;
    std::vector<Scope> m_closure_scope_stack;

  public:
    inline Scoper(GCTFE& gc_tfe, DefTable& gdef_tab, PlatformProcTable& pproc_tab);
  
  public:
    OBJECT rw_expr_stx(OBJECT expr_stx);

  private:
    // pushes a fresh scope containing the given symbols
    void push_scope();
    
    // returns a unique list of free variables referenced
    std::vector<Nonlocal> pop_scope();
    
    // defines a local variable in the current scope
    LDefID define_local(FLoc loc, IntStr name);

    // defines a global variable
    GDefID define_global(FLoc loc, IntStr name);
    
    // defines a local or global variable depending on the current scope stack.
    // RelVarScope is either Local or Global, indicating where the symbol was defined.
    std::pair<RelVarScope, size_t> define(FLoc loc, IntStr name); 

    // looks up a variable, returning the scope it was found in and an ID
    // - if local, then (RelVarScope::Local, LDefID)
    // - if nonlocal, then (RelVarScope::Free, LDefID) 
    // - if global, then (RelVarScope::Global, GDefID)
    std::pair<RelVarScope, size_t> refer(FLoc loc, OBJECT symbol, bool is_mut = false);

  private:
    OBJECT rw_const_expr_stx(OBJECT expr_stx);
    OBJECT rw_id_expr_stx_data(FLoc loc, OBJECT expr_stx_data);
    OBJECT rw_pair_expr_stx(OBJECT expr_stx);
    OBJECT rw_pair_stx_data(FLoc loc, OBJECT expr_stx_data);
    OBJECT rw_list_stx_data(FLoc loc, OBJECT expr_stx_data);
    OBJECT rw_list_stx_data__lambda(FLoc loc, OBJECT expr_stx_data);
    OBJECT rw_list_stx_data__if(OBJECT expr_stx_data);
    OBJECT rw_list_stx_data__set(FLoc loc, OBJECT expr_stx_data);
    OBJECT rw_list_stx_data__call_cc(OBJECT expr_stx_data);
    OBJECT rw_list_stx_data__define(FLoc loc, OBJECT expr_stx_data);
    OBJECT rw_list_stx_data__p_invoke(FLoc loc, OBJECT expr_stx_data);
    OBJECT rw_list_stx_data__begin(FLoc loc, OBJECT expr_stx_data);
    OBJECT rw_list_stx_data__apply(FLoc loc, OBJECT expr_stx_data);
  
  private:
    bool in_global_scope() const { return m_closure_scope_stack.empty(); }
  };
  
  inline Scoper::Scoper(GCTFE& gc_tfe, DefTable& def_tab, PlatformProcTable& pproc_tab)
  : m_gc_tfe(gc_tfe),
    m_def_tab(def_tab),
    m_pproc_tab(pproc_tab),
    m_closure_scope_stack()
  {
    m_closure_scope_stack.reserve(256);
  }
  
  void Scoper::push_scope() {
    m_closure_scope_stack.emplace_back();
  }

  std::vector<Nonlocal> Scoper::pop_scope() {
    auto res = std::move(m_closure_scope_stack.back().inuse_nonlocal_defs);
    m_closure_scope_stack.pop_back();
    return res;
  }

  LDefID Scoper::define_local(FLoc loc, IntStr name) {
    assert(!m_closure_scope_stack.empty());
    auto old_def = m_closure_scope_stack.back().locals.idx(name);
    if (old_def.has_value()) {
      std::stringstream s;
      s << "Local variable re-defined in scope: " << interned_string(name) << std::endl
        << "new: " << loc.as_text() << std::endl
        << "old: " << m_def_tab.local(old_def.value()).loc().as_text();
      error(s.str());
      throw SsiError();
    } else {
      LDefID ldef_id = m_def_tab.define_local(loc, name);
      m_closure_scope_stack.back().locals.add(name);
      m_closure_scope_stack.back().local_defs.push_back(ldef_id);
      return ldef_id;
    }
  }

  GDefID Scoper::define_global(FLoc loc, IntStr name) {
    assert(m_closure_scope_stack.empty());
    auto old_def = m_def_tab.lookup_global_id(name);
    if (old_def.has_value()) {
      std::stringstream s;
      s << "Global variable re-defined: " << interned_string(name) << std::endl
        << "new: " << loc.as_text() << std::endl
        << "old: " << m_def_tab.global(old_def.value()).loc().as_text() << std::endl
        << "HINT: to update an existing value, use 'set!' instead.";
      error(s.str());
      throw SsiError();
    } else {
      return m_def_tab.define_global(loc, name);
    }
  }

  std::pair<RelVarScope, size_t> Scoper::define(FLoc loc, IntStr name) {
    if (in_global_scope()) {
      return {RelVarScope::Global, define_global(loc, name)};
    } else {
      return {RelVarScope::Local, define_local(loc, name)};
    }
  }
  
  inline std::pair<RelVarScope, size_t> Scoper::refer(FLoc loc, OBJECT symbol, bool is_mut) {
    // compile-time type-checks
    if (!symbol.is_interned_symbol()) {
      error("broken query symbol in refer: expected symbol");
      throw SsiError();
    }
    
    std::cerr << "REFER: " << symbol << std::endl;

    IntStr sym = symbol.as_interned_symbol();

    // checking 'locals'
    if (!m_closure_scope_stack.empty()) {
      Scope& top = m_closure_scope_stack.back();
      auto opt_idx = top.locals.idx(sym);
      if (opt_idx.has_value()) {
        LDefID ldef_id = top.local_defs[opt_idx.value()];
        return {RelVarScope::Local, ldef_id};
      }
    }

    // checking 'free', trying to get index:
    if (!m_closure_scope_stack.empty()) {
      Scope& top = m_closure_scope_stack.back();
      auto opt_cached_idx = top.inuse_nonlocals.idx(sym);
      if (opt_cached_idx.has_value()) {
        auto cached_idx = opt_cached_idx.value();
        auto& nonlocal = top.inuse_nonlocal_defs[cached_idx];
        if (is_mut) {
          nonlocal.use_is_mut |= true;
        }
        LDefID ldef_id = nonlocal.ldef_id;
        return {RelVarScope::Free, ldef_id};
      } else {
        // must check whole scope stack, and if found, must insert into 'inuse' table
        ssize_t found_idx = -1;
        LDefID found_ldef_id = static_cast<LDefID>(-1);
        bool found_ldef_is_mut = false;
        for (ssize_t i = m_closure_scope_stack.size()-2; i >= 0; i--) {
          auto opt_idx = m_closure_scope_stack[i].locals.idx(sym);
          if (opt_idx.has_value()) {
            found_idx = opt_idx.value();
            auto const& nonlocal = m_closure_scope_stack[i].inuse_nonlocal_defs[found_idx];
            found_ldef_id = nonlocal.ldef_id;
            found_ldef_is_mut = nonlocal.use_is_mut;
            break;
          }
        }
        if (found_idx >= 0) {
          // insert into 'inuse' table, then return
          top.inuse_nonlocals.add(sym);
          top.inuse_nonlocal_defs.emplace_back(found_ldef_id, found_ldef_is_mut);
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
      ss << "Lookup failed: symbol used but not defined: " << symbol << std::endl;
      ss << "see: " << loc.as_text();
      error(ss.str());
      throw SsiError();
    }
  }

  OBJECT Scoper::rw_expr_stx(OBJECT expr_stx) {
    std::cerr << "RW: " << expr_stx << std::endl;

    assert(expr_stx.is_syntax());
    auto expr_stx_p = expr_stx.as_syntax_p();
    OBJECT data = expr_stx_p->data();
    if (data.is_interned_symbol()) {
      auto res = rw_id_expr_stx_data(expr_stx_p->loc(), data);
      std::cerr << "-> " << res << std::endl;
      return res;
    }
    if (data.is_pair()) {
      auto new_data = rw_pair_stx_data(expr_stx_p->loc(), data);
      auto res = OBJECT::make_syntax(&m_gc_tfe, new_data, expr_stx_p->loc());
      std::cerr << "-> " << res << std::endl;
      return res;
    }
    auto res = rw_const_expr_stx(expr_stx);
    std::cerr << "-> " << res << std::endl;
    return res;
  }
  OBJECT Scoper::rw_id_expr_stx_data(FLoc loc, OBJECT expr_stx_data) {
    assert(expr_stx_data.is_interned_symbol());
    auto [rel_var_scope, def_id] = refer(loc, expr_stx_data);
    IntStr rel_var_scope_sym = rel_var_scope_to_sym(rel_var_scope);
    auto res = OBJECT::make_syntax(
      &m_gc_tfe,
      list(&m_gc_tfe, 
        OBJECT::make_interned_symbol(g_id_cache().reference),
        OBJECT::make_interned_symbol(rel_var_scope_sym),
        OBJECT::make_integer(def_id)
      ),
      loc
    );
    return res;
  }
  OBJECT Scoper::rw_const_expr_stx(OBJECT expr_stx) {
    assert(expr_stx.is_syntax());
    return expr_stx;
  }
  OBJECT Scoper::rw_pair_stx_data(FLoc loc, OBJECT expr_stx_data) {
    auto obj = expr_stx_data.as_pair_p();

    OBJECT car_syntax = obj->car();
    OBJECT cdr = obj->cdr();

    if (cdr.is_list()) {
      return rw_list_stx_data(loc, expr_stx_data);
    } else {
      return cons(
        &m_gc_tfe,
        rw_expr_stx(car_syntax),
        rw_expr_stx(cdr)
      );
    }
  }
  OBJECT Scoper::rw_list_stx_data__lambda(FLoc loc, OBJECT expr_stx_data) {
    assert(expr_stx_data.is_pair());
    auto args = extract_args<3>(expr_stx_data);
    auto lambda_syntax = args[0];
    auto vars_syntax = args[1];
    auto body_syntax = args[2];

    assert(vars_syntax.is_syntax());
    auto vars_syntax_p = vars_syntax.as_syntax_p();

    assert(body_syntax.is_syntax());
    // auto body_syntax_p = body_syntax.as_pair_p();

    OBJECT vars_syntax_d = vars_syntax_p->data();

    OBJECT vars = vars_syntax_p->to_datum(&m_gc_tfe);
    check_vars_list_else_throw(loc, vars);

    std::vector<std::pair<LDefID, FLoc>> args_vec;
    args_vec.reserve(10);
    OBJECT rewritten_body_stx;
    push_scope();
    {
      for (OBJECT args = vars_syntax_d; !args.is_null(); args = cdr(args)) {
        OBJECT arg = car(args);
        assert(arg.is_syntax());
        auto arg_p = arg.as_syntax_p();
        OBJECT arg_name = arg_p->data();
        assert(arg_name.is_interned_symbol());
        LDefID ldef_id = define_local(arg_p->loc(), arg_name.as_interned_symbol());
        args_vec.push_back({ldef_id, arg_p->loc()});
      }

      // ensuring we scope the body while the formal argument scope is pushed
      // - any 'define' gets added to this scope
      // - any mutation gets registered in this scope
      rewritten_body_stx = rw_expr_stx(body_syntax);
    }
    auto nonlocals_vec = pop_scope();
    
    // assembling 'nonlocals' list:
    OBJECT nonlocals = OBJECT::null;
    for (Nonlocal const& nonlocal: nonlocals_vec) {
      auto element = cons(   // (nonlocal-ldef-id . use-is-mut)
        &m_gc_tfe,
        OBJECT::make_interned_symbol(nonlocal.ldef_id), 
        OBJECT::make_boolean(nonlocal.use_is_mut)
      );
      nonlocals = cons(&m_gc_tfe, element, nonlocals);
    }

    // assembling 'vars' list (args):
    OBJECT res_args = OBJECT::null;
    for (auto [ldef_id, loc]: args_vec) {
      auto element = OBJECT::make_syntax(
        &m_gc_tfe,
        OBJECT::make_integer(ldef_id),
        loc
      );
      res_args = cons(&m_gc_tfe, element, res_args);
    }

    // (lambda #'(formal-vars) '(bound-vars) #'body)
    return list(&m_gc_tfe, 
      lambda_syntax,      // lambda, but a syntax object
      res_args,           // note: replaced ID in syntax object with an integer LDefID
      nonlocals,          // note: not syntax objects since synthetic
      rewritten_body_stx  // body after scoping, expanding
    );
  }
  OBJECT Scoper::rw_list_stx_data__if(OBJECT expr_stx_data) {
    auto args = extract_args<4>(expr_stx_data);
    auto if_kw_stx = args[0];
    auto cond_stx = args[1];
    auto then_stx = args[2];
    auto else_stx = args[3];
    return list(
      &m_gc_tfe,
      if_kw_stx,    // if, but a syntax object
      rw_expr_stx(cond_stx),
      rw_expr_stx(then_stx),
      rw_expr_stx(else_stx)
    );
  }
  OBJECT Scoper::rw_list_stx_data__set(FLoc loc, OBJECT expr_stx_data) {
    // (mutation ,rel-var-scope ,def-id)
    auto args = extract_args<3>(expr_stx_data);
    auto name_obj_stx = args[1];
    auto init_obj_stx = args[2];

    assert(name_obj_stx.is_syntax());
    assert(init_obj_stx.is_syntax());
    
    auto name_obj = name_obj_stx.as_syntax_p()->data();
    if (!name_obj.is_interned_symbol()) {
      std::stringstream ss;
      ss << "set!: expected first argument to be a symbol, got: " << name_obj << std::endl;
      ss << "see: " << loc.as_text();
      error(ss.str());
      throw SsiError();
    }
    IntStr name = name_obj.as_interned_symbol();
    auto [rel_var_scope, def_id] = refer(loc, name, true);
    
    auto mutation_obj = OBJECT::make_interned_symbol(g_id_cache().mutation);
    auto rel_var_scope_sym = rel_var_scope_to_sym(rel_var_scope);
    auto rel_var_scope_sym_obj = OBJECT::make_interned_symbol(rel_var_scope_sym);
    auto def_id_obj = OBJECT::make_integer(def_id);
    return list(
      &m_gc_tfe, 
      mutation_obj, rel_var_scope_sym_obj, def_id_obj,
      rw_expr_stx(init_obj_stx)
    );
  }
  OBJECT Scoper::rw_list_stx_data__call_cc(OBJECT expr_stx_data) {
    auto args = extract_args<2>(expr_stx_data);
    auto kw_call_cc_stx = args[0];
    auto continuation_cb_stx = args[1];
    return list(&m_gc_tfe,
      kw_call_cc_stx,
      rw_expr_stx(continuation_cb_stx)
    );
  }
  OBJECT Scoper::rw_list_stx_data__define(FLoc loc, OBJECT expr_stx_data) {
    auto args = extract_args<3>(expr_stx_data);
    auto define_kw_stx = args[0];
    auto name_obj_stx = args[1];
    auto init_obj_stx = args[2];

    assert(name_obj_stx.is_syntax());
    auto name_obj_stx_p = name_obj_stx.as_syntax_p();
    auto name_obj = name_obj_stx_p->data();
    if (!name_obj.is_interned_symbol()) {
      std::stringstream s;
      s << "define: expected first arg to be name symbol, got: " 
        << name_obj_stx_p->to_datum(&m_gc_tfe) << std::endl;
      s << "see: " << loc.as_text();
      error(s.str());
      throw SsiError();
    }

    IntStr name = name_obj.as_interned_symbol();
    auto [rel_var_scope, def_id] = define(loc, name);
    auto def_id_obj = OBJECT::make_integer(def_id);
    auto rel_var_scope_sym = rel_var_scope_to_sym(rel_var_scope);
    auto rel_var_scope_sym_obj = OBJECT::make_interned_symbol(rel_var_scope_sym);
    auto def_id_obj_stx = OBJECT::make_syntax(
      &m_gc_tfe,
      def_id_obj,
      name_obj_stx_p->loc()
    );

    return list(&m_gc_tfe,
      define_kw_stx,                // define
      rel_var_scope_sym_obj,        // rel-var-scope
      def_id_obj_stx,               // stx replacing IntStr name with GDefID
      rw_expr_stx(init_obj_stx)     // initializer
    );
  }
  OBJECT Scoper::rw_list_stx_data__p_invoke(FLoc loc, OBJECT expr_stx_data) {
    auto args = extract_args<2>(expr_stx_data, true);
    auto p_invoke_stx = args[0];
    auto proc_name_obj_stx = args[1];
    auto proc_name_obj_stx_p = proc_name_obj_stx.as_syntax_p();
    assert(proc_name_obj_stx.is_syntax());
    auto proc_name_obj = proc_name_obj_stx_p->data();
    
    if (!proc_name_obj.is_interned_symbol()) {
      std::stringstream s;
      s << "p/invoke: expected first arg to be name symbol, got: " 
        << proc_name_obj_stx_p->to_datum(&m_gc_tfe) << std::endl
        << "see: " << loc.as_text();
      error(s.str());
      throw SsiError();
    }

    IntStr proc_name = proc_name_obj.as_interned_symbol();
    auto opt_pproc_id = m_pproc_tab.lookup(proc_name);
    if (!opt_pproc_id.has_value()) {
      std::stringstream s;
      s << "p/invoke: unbound platform procedure referenced: " 
        << proc_name_obj << std::endl
        << "see: " << loc.as_text();
      error(s.str());
      throw SsiError();
    }
    PlatformProcID pproc_id = opt_pproc_id.value();
    auto pproc_id_obj = OBJECT::make_integer(pproc_id);

    return list(&m_gc_tfe,
      p_invoke_stx,   // p/invoke syntax
      OBJECT::make_syntax(&m_gc_tfe, pproc_id_obj, proc_name_obj_stx_p->loc())
    );
  }
  OBJECT Scoper::rw_list_stx_data__begin(FLoc loc, OBJECT expr_stx_data) {
    bool is_global = in_global_scope();

    if (!expr_stx_data.is_pair()) {
      std::stringstream s;
      s << "begin: expected at least 1 expression to evaluate, got 0 OR improper list" << std::endl
        << "see: " << loc.as_text();
      throw SsiError();
    }

    // if (begin ...) in top-level scope (i.e. not under a closure), then definitions
    // apply to the global scope, otherwise local to a scope unique to this 'begin'
    OBJECT rewritten_elements = OBJECT::null;
    if (!is_global) { push_scope(); }
    {
      for (OBJECT rem = cdr(expr_stx_data); !rem.is_null(); rem = cdr(rem)) {
        if (!rem.is_pair()) {
          std::stringstream ss;
          ss << "begin: expected a pair-list, got improper pair-list" << std::endl;
          ss << "item: " << rem << std::endl;
          ss << "see:  " << loc.as_text() << std::endl;
          error(ss.str());
          throw SsiError();
        }

        OBJECT old_stx_obj = car(rem);
        OBJECT new_stx_obj = rw_expr_stx(old_stx_obj);
        rewritten_elements = cons(&m_gc_tfe, new_stx_obj, rewritten_elements);
      }
    }
    if (!is_global) { pop_scope(); }

    return cons(&m_gc_tfe, car(expr_stx_data), rewritten_elements);
  }
  OBJECT Scoper::rw_list_stx_data__apply(FLoc loc, OBJECT expr_stx_data) {
    SUPPRESS_UNUSED_VARIABLE_WARNING(loc);
    auto expr_items = list_to_cpp_vector(expr_stx_data);
    std::vector<OBJECT> rw_items;
    rw_items.reserve(expr_items.size());
    for (OBJECT arg: expr_items) {
      rw_items.push_back(rw_expr_stx(arg));
    }
    return cpp_vector_to_list(&m_gc_tfe, rw_items);
  }
  OBJECT Scoper::rw_list_stx_data(FLoc loc, OBJECT expr_stx_data) {
    auto expr_stx_data_p = expr_stx_data.as_pair_p();

    if (!expr_stx_data_p->car().is_syntax()) {
      // synthetic form
      assert(expr_stx_data_p->car().is_interned_symbol());
      if (expr_stx_data_p->car().as_interned_symbol() == g_id_cache().reference) {
        return expr_stx_data;
      }
      error("compiler-error: unknown synthetic syntax atom");
      throw SsiError();
    }

    OBJECT head_syntax = expr_stx_data_p->car();
    auto head_syntax_p = head_syntax.as_syntax_p();
    OBJECT head = head_syntax_p->data();

    if (head.is_interned_symbol()) {
      auto keyword_symbol_id = head.as_interned_symbol();

      // lambda
      if (keyword_symbol_id == g_id_cache().lambda) {
        return rw_list_stx_data__lambda(loc, expr_stx_data);
      }

      // if
      if (keyword_symbol_id == g_id_cache().if_) {
        return rw_list_stx_data__if(expr_stx_data);
      }

      // set!
      if (keyword_symbol_id == g_id_cache().set) {
        return rw_list_stx_data__set(loc, expr_stx_data);
      }

      // call/cc
      if (keyword_symbol_id == g_id_cache().call_cc) {
        return rw_list_stx_data__call_cc(expr_stx_data);
      }

      // define
      if (keyword_symbol_id == g_id_cache().define) {
        return rw_list_stx_data__define(loc, expr_stx_data);
      }

      // p/invoke
      if (keyword_symbol_id == g_id_cache().p_invoke) {
        return rw_list_stx_data__p_invoke(loc, expr_stx_data);
      }

      // begin
      if (keyword_symbol_id == g_id_cache().begin) {
        return rw_list_stx_data__begin(loc, expr_stx_data);
      }

      // quote
      if (keyword_symbol_id == g_id_cache().quote) {
        return expr_stx_data;
      }

      // fallthrough
    }

    // apply:
    // TODO: detect macro application
    return rw_list_stx_data__apply(loc, expr_stx_data);
  }
}

//
// Impl: macroexpand
//

namespace ss {
  std::vector<OBJECT> macroexpand_syntax_impl(
    GcThreadFrontEnd& gc_tfe,
    DefTable& def_tab,
    PlatformProcTable& pproc_tab,
    std::vector<OBJECT> expr_stx_vec
  ) {
    std::vector<OBJECT> out_expr_stx_vec;
    Scoper scoper{gc_tfe, def_tab, pproc_tab};
    out_expr_stx_vec.reserve(expr_stx_vec.size());
    for (OBJECT expr_stx: expr_stx_vec) {
      out_expr_stx_vec.push_back(scoper.rw_expr_stx(expr_stx));
    }
    return out_expr_stx_vec;
  }
}

//
// Interface:
//

namespace ss {
  std::vector<OBJECT> macroexpand_syntax(
    GcThreadFrontEnd& gc_tfe,
    DefTable& def_tab,
    PlatformProcTable& pproc_tab,
    std::vector<OBJECT> expr_stx_vec
  ) {
    return macroexpand_syntax_impl(
      gc_tfe, def_tab, pproc_tab,
      std::move(expr_stx_vec)
    );
  }
}
