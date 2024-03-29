// cf https://www.gnu.org/software/guile/manual/html_node/Syntax-Case.html
// This module handles 2 jobs: resolving lexical scoping and macro expansion.
// Rather than an iterative approach, we fully, recursively expand each line
// before moving to the next one.
// It performs the following rewrites in parallel:
// - To resolve scoping, reference symbols are replaced by the list
//   Treated as a pseudo-atom
//    `(reference ,rel-var-scope ,def-id)
// - Similarly, 'set!' is replaced by the pseudo-atom
//    `(mutation ,rel-var-scope ,def-id ,scoped-initializer-stx)
// - To avoid store scoping information, free-vars, and mutables, lambdas are 
//   rewritten as:
//   (expanded-lambda #'(args) '(bound-free-vars) #'body)
//   Note that bound-free-vars is an ordered list of pair objects, not syntax 
//   objects. In fact, each bound-free-var element is a list (cf Nonlocal).
//   Each args element is an ldef-id integer wrapped in a SyntaxObject; we 
//   replace ID by an int FixNum.
// - Similarly, 'define' is replaced 
//    (expanded-define ,rel-var-scope #,def-id #,scoped-initializer-stx)
// - Similarly, 'p/invoke' is replaced
//    (expanded-p/invoke #,pproc-id #,args ...)
// - Macros are expanded recursively and completely, line-by-line.
//   This means we will not proceed to line N+1 until line N is fully expanded.
// - As an optimization, we rewrite
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
    RelVarScope parent_rel_var_scope;
    ssize_t idx_in_parent_scope;
    LDefID ldef_id;
    bool use_is_mut;
  public:
    Nonlocal(
      RelVarScope parent_rel_var_scope,
      ssize_t idx_in_parent_scope,
      LDefID ldef_id, 
      bool use_is_mut
    )
    : parent_rel_var_scope(parent_rel_var_scope),
      idx_in_parent_scope(idx_in_parent_scope),
      ldef_id(ldef_id),
      use_is_mut(use_is_mut)
    {}
  };

  struct Scope {
  public:
    OrderedSymbolSet locals_ordered_set;
    std::vector<LDefID> local_defs;
    OrderedSymbolSet inuse_nonlocal_ordered_set;
    std::vector<Nonlocal> inuse_nonlocal_defs;
  public:
    Scope()
    : locals_ordered_set(),
      local_defs(),
      inuse_nonlocal_ordered_set(),
      inuse_nonlocal_defs()
    {
      assert(locals_ordered_set.size() == local_defs.size());
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
    // rewrites a syntax object's data, returning new data
    OBJECT rw_expr_stx_data(FLoc loc, OBJECT expr_stx);
    
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
    std::pair<RelVarScope, size_t> lookup_defn(FLoc loc, IntStr symbol, bool is_mut, size_t offset = 0);

  private:
    OBJECT rw_id_expr_stx_data(FLoc loc, OBJECT expr_stx_data);
    OBJECT rw_pair_expr_stx(OBJECT expr_stx);
    OBJECT rw_pair_stx_data(FLoc loc, OBJECT expr_stx_data);
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
    auto old_def = m_closure_scope_stack.back().locals_ordered_set.idx(name);
    if (old_def.has_value()) {
      std::stringstream s;
      s << "Local variable re-defined in scope: " << interned_string(name) << std::endl
        << "new: " << loc.as_text() << std::endl
        << "old: " << m_def_tab.local(old_def.value()).loc().as_text();
      error(s.str());
      throw SsiError();
    } else {
      LDefID ldef_id = m_def_tab.define_local(loc, name);
      m_closure_scope_stack.back().locals_ordered_set.add(name);
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
  
  inline std::pair<RelVarScope, size_t> Scoper::lookup_defn(
    FLoc loc, 
    IntStr sym, 
    bool is_mut, 
    size_t offset
  ) {
    // checking 'locals' unless in global scope already:
    if (m_closure_scope_stack.size() > offset) {
      Scope& top = m_closure_scope_stack[m_closure_scope_stack.size()-1 - offset];
      auto opt_idx = top.locals_ordered_set.idx(sym);
      if (opt_idx.has_value()) {
        return {RelVarScope::Local, opt_idx.value()};
      }
    }
    
    // checking 'free' unless in top-most function already:
    // NOTE: what about 'begin'? It never pushes a new scope. This means that
    // nested begins' definitions _will_ conflict.
    if (m_closure_scope_stack.size() > 1+offset) {
      // seeing if this is a free variable that has been referred in this closure
      // already:
      Scope& top_scope = m_closure_scope_stack[m_closure_scope_stack.size()-1 - offset];
      auto opt_cached_idx = top_scope.inuse_nonlocal_ordered_set.idx(sym);
      if (opt_cached_idx.has_value()) {
        auto cached_idx = opt_cached_idx.value();
        auto& nonlocal = top_scope.inuse_nonlocal_defs[cached_idx];
        if (is_mut) {
          nonlocal.use_is_mut |= true;
        }
        return {RelVarScope::Free, cached_idx};
      } else {
        // must check whole scope stack, and if found, must insert into 'inuse' table
        LDefID found_ldef_id = static_cast<LDefID>(-1);
        auto [parent_rel_var_scope, found_idx] = lookup_defn(loc, sym, is_mut, 1+offset);
        if (parent_rel_var_scope == RelVarScope::Global) {
          return {RelVarScope::Global, found_idx};
        }

        // insert fresh into top 'inuse_nonlocals' table, then return
        ssize_t nonlocal_idx = static_cast<ssize_t>(top_scope.inuse_nonlocal_defs.size());
        top_scope.inuse_nonlocal_ordered_set.add(sym);
        top_scope.inuse_nonlocal_defs.emplace_back(
          parent_rel_var_scope,
          found_idx,
          found_ldef_id, 
          is_mut
        );
        return {RelVarScope::Free, nonlocal_idx};
      }
    }

    // checking globals
    {
      auto opt_gdef_id = m_def_tab.lookup_global_id(sym);
      if (opt_gdef_id.has_value()) {
        return {RelVarScope::Global, opt_gdef_id.value()};
      }
    }
    
    // lookup failed:
    {
      std::stringstream ss;
      ss << "Lookup failed: symbol used but not defined: '" << interned_string(sym) << std::endl;
      ss << "see: " << loc.as_text();
      error(ss.str());
      throw SsiError();
    }
  }

  OBJECT Scoper::rw_expr_stx(OBJECT expr_stx) {
    assert(expr_stx.is_syntax());
    auto expr_stx_p = expr_stx.as_syntax_p();
    return OBJECT::make_syntax(&m_gc_tfe,
      rw_expr_stx_data(expr_stx_p->loc(), expr_stx_p->data()),
      expr_stx_p->loc()
    );
  }
  OBJECT Scoper::rw_expr_stx_data(FLoc loc, OBJECT expr_stx_data) {
    // std::cerr << "RWs " << expr_stx_data << std::endl;
    if (expr_stx_data.is_symbol()) {
      auto res = rw_id_expr_stx_data(loc, expr_stx_data);      
      // std::cerr << "RWf " << expr_stx_data << std::endl;
      // std::cerr << "1-> " << res << std::endl;
      return res;
    }
    else if (expr_stx_data.is_pair()) {
      auto new_data = rw_pair_stx_data(loc, expr_stx_data);
      // std::cerr << "RWf " << expr_stx_data << std::endl;
      // std::cerr << "2-> " << new_data << std::endl;
      return new_data;
    }
    else {
      // std::cerr << "RWf " << expr_stx_data << std::endl;
      // std::cerr << "3-> " << expr_stx_data << std::endl;
      return expr_stx_data;
    }
  }
  OBJECT Scoper::rw_id_expr_stx_data(FLoc loc, OBJECT expr_stx_data) {
    assert(expr_stx_data.is_symbol());
    auto sym = expr_stx_data.as_symbol();
    auto [rel_var_scope, def_id] = lookup_defn(loc, sym, false);
    IntStr rel_var_scope_sym = rel_var_scope_to_sym(rel_var_scope);
    auto res = list(&m_gc_tfe, 
      OBJECT::make_symbol(g_id_cache().reference),
      OBJECT::make_symbol(rel_var_scope_sym),
      OBJECT::make_integer(def_id)
    );
    return res;
  }
  OBJECT Scoper::rw_list_stx_data__lambda(FLoc loc, OBJECT expr_stx_data) {
    assert(expr_stx_data.is_pair());
    auto args = extract_args<3>(expr_stx_data);
    // auto lambda_syntax = args[0];
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
        assert(arg_name.is_symbol());
        LDefID ldef_id = define_local(arg_p->loc(), arg_name.as_symbol());
        args_vec.push_back({ldef_id, arg_p->loc()});
      }

      // ensuring we scope the body while the formal argument scope is pushed
      // - any 'define' gets added to this scope
      // - any lookup + opt mutation gets registered in this scope as free var
      rewritten_body_stx = rw_expr_stx(body_syntax);
    }
    auto nonlocals_vec = pop_scope();

    // assembling 'nonlocals' list:
    // TODO: confirm if reverse-order here is expected.
    OBJECT nonlocals = OBJECT::null;
    for (Nonlocal const& nonlocal: nonlocals_vec) {
      auto element = list(   // (parent-rel-var-scope parent-idx use-is-mut ldef-id)
        &m_gc_tfe,
        OBJECT::make_symbol(rel_var_scope_to_sym(nonlocal.parent_rel_var_scope)),
        OBJECT::make_integer(nonlocal.idx_in_parent_scope),
        OBJECT::make_boolean(nonlocal.use_is_mut),
        OBJECT::make_symbol(nonlocal.ldef_id)
      );
      nonlocals = cons(&m_gc_tfe, element, nonlocals);
    }

    // assembling 'vars' list (args):
    // TODO: confirm if reverse-order here is expected.
    OBJECT res_args = OBJECT::null;
    for (auto [ldef_id, loc]: args_vec) {
      auto element = OBJECT::make_syntax(
        &m_gc_tfe,
        OBJECT::make_integer(ldef_id),
        loc
      );
      res_args = cons(&m_gc_tfe, element, res_args);
    }

    // (expanded-lambda #'(formal-vars) '(bound-vars) #'body)
    auto expanded_lambda = OBJECT::make_symbol(g_id_cache().expanded_lambda);
    return list(&m_gc_tfe, 
      expanded_lambda,          // expanded-lambda
      res_args,                 // note: replaced ID in syntax object with an integer LDefID
      nonlocals,                // note: not syntax objects since synthetic
      rewritten_body_stx        // body after scoping, expanding
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
    
    // resolving the definition for this symbol:
    auto name_obj = name_obj_stx.as_syntax_p()->data();
    if (!name_obj.is_symbol()) {
      std::stringstream ss;
      ss << "set!: expected first argument to be a symbol, got: " << name_obj << std::endl;
      ss << "see: " << loc.as_text();
      error(ss.str());
      throw SsiError();
    }
    IntStr name = name_obj.as_symbol();
    auto [rel_var_scope, def_id] = lookup_defn(loc, name, true);

    // updating this definition's properties to indicate that it may be mutated 
    // at some point during execution:
    switch (rel_var_scope) {
      case RelVarScope::Local:
      case RelVarScope::Free:
        m_def_tab.mark_local_defn_mutated(def_id);
        break;
      case RelVarScope::Global:
        m_def_tab.mark_global_defn_mutated(def_id);
        break;
      default:
        error("Unknown set target rel_var_scope when rewriting 'set!'");
        throw SsiError();
    }

    // creating the replacement 'mutation' term:
    auto mutation_obj = OBJECT::make_symbol(g_id_cache().mutation);
    auto rel_var_scope_sym = rel_var_scope_to_sym(rel_var_scope);
    auto rel_var_scope_sym_obj = OBJECT::make_symbol(rel_var_scope_sym);
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
    // auto define_kw_stx = args[0];
    auto name_obj_stx = args[1];
    auto init_obj_stx = args[2];

    assert(name_obj_stx.is_syntax());
    auto name_obj_stx_p = name_obj_stx.as_syntax_p();
    auto name_obj = name_obj_stx_p->data();
    if (!name_obj.is_symbol()) {
      std::stringstream s;
      s << "define: expected first arg to be name symbol, got: " 
        << name_obj_stx_p->to_datum(&m_gc_tfe) << std::endl;
      s << "see: " << loc.as_text();
      error(s.str());
      throw SsiError();
    }

    IntStr name = name_obj.as_symbol();
    auto [rel_var_scope, def_id] = define(loc, name);
    auto def_id_obj = OBJECT::make_integer(def_id);
    auto rel_var_scope_sym = rel_var_scope_to_sym(rel_var_scope);
    auto rel_var_scope_sym_obj = OBJECT::make_symbol(rel_var_scope_sym);
    auto def_id_obj_stx = OBJECT::make_syntax(
      &m_gc_tfe,
      def_id_obj,
      name_obj_stx_p->loc()
    );

    OBJECT expanded_define_kw = OBJECT::make_symbol(g_id_cache().expanded_define);
    return list(&m_gc_tfe,
      expanded_define_kw,           // expanded-define
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
    
    if (!proc_name_obj.is_symbol()) {
      std::stringstream s;
      s << "p/invoke: expected first arg to be name symbol, got: " 
        << proc_name_obj_stx_p->to_datum(&m_gc_tfe) << std::endl
        << "see: " << loc.as_text();
      error(s.str());
      throw SsiError();
    }

    IntStr proc_name = proc_name_obj.as_symbol();
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

    OBJECT rem;
    std::vector<OBJECT> expanded_args;
    expanded_args.reserve(10);
    for (rem = cddr(expr_stx_data); !rem.is_null(); rem = cdr(rem)) {
      expanded_args.push_back(rw_expr_stx(car(rem)));
    }

    // cons-ing together the list in reverse-order:
    OBJECT res = OBJECT::null;
    for (auto it = expanded_args.rbegin(); it != expanded_args.rend(); it++) {
      res = cons(&m_gc_tfe, *it, res);
    }
    res = cons(&m_gc_tfe,
      OBJECT::make_syntax(&m_gc_tfe, pproc_id_obj, proc_name_obj_stx_p->loc()),
      res
    );

    // adding the 'expanded-pinvoke' prefix and returning:
    res = cons(
      &m_gc_tfe, 
      OBJECT::make_syntax(
        &m_gc_tfe, 
        OBJECT::make_symbol(g_id_cache().expanded_p_invoke),
        p_invoke_stx.as_syntax_p()->loc()
      ), 
      res
    );

    return res;
  }
  OBJECT Scoper::rw_list_stx_data__begin(FLoc loc, OBJECT expr_stx_data) {
    if (!expr_stx_data.is_pair()) {
      std::stringstream s;
      s << "begin: expected at least 1 expression to evaluate, got 0 OR improper list" << std::endl
        << "see: " << loc.as_text();
      throw SsiError();
    }

    // if (begin ...) in top-level scope (i.e. not under a closure), then definitions
    // apply to the global scope, otherwise local to a scope unique to this 'begin'.
    // NOTE: do NOT push_scope; this will cause variables that are actually locals
    // to be resolved as nonlocals.
    // NOTE: this decision means that definitions in nested 'begin' terms will clash.
    OBJECT rewritten_elements = OBJECT::null;
    {
      std::vector<OBJECT> items;
      items.reserve(list_length(cdr(expr_stx_data)));
    
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
        items.push_back(new_stx_obj);
      }

      while (!items.empty()) {
        rewritten_elements = cons(&m_gc_tfe, items.back(), rewritten_elements);
        items.pop_back();
      }
    }
    
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
  OBJECT Scoper::rw_pair_stx_data(FLoc loc, OBJECT expr_stx_data) {
    auto expr_stx_data_p = expr_stx_data.as_pair_p();

    if (!expr_stx_data_p->car().is_syntax()) {
      // synthetic form
      assert(expr_stx_data_p->car().is_symbol());
      if (expr_stx_data_p->car().as_symbol() == g_id_cache().reference) {
        return expr_stx_data;
      }
      error("compiler-error: unknown synthetic syntax atom");
      throw SsiError();
    }

    OBJECT head_syntax = expr_stx_data_p->car();
    auto head_syntax_p = head_syntax.as_syntax_p();
    OBJECT head = head_syntax_p->data();

    if (head.is_symbol()) {
      auto keyword_symbol_id = head.as_symbol();

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
