// cf https://www.gnu.org/software/guile/manual/html_node/Syntax-Case.html
// This module handles 2 jobs: resolving lexical scoping and macro expansion.
// This module accepts a syntax object with env '#f' and rewrites it 
// (creates copy with changes) to include envs. If an env is already provided
// then it is preserved instead.
// We exclude the templates of `syntax-case` from scoping, only scoping to
// copy for instantiation.

#include <vector>

#include "ss-core/common.hh"
#include "ss-core/expander.hh"
#include "ss-core/gc.hh"

//
// Impl: common utility
//

namespace ss {
  using GCTFE = GcThreadFrontEnd;
}

//
// Impl: scoper
//

namespace ss {
  
  class Scope {
  private:
    std::vector<IntStr> locals;
    std::vector<IntStr> nonlocals;
  };

  class Scoper {
  private:
    GCTFE& m_gc_tfe;
  public:
    Scoper(GCTFE& gc_tfe);
  public:
    std::pair<RelVarScope, size_t> Scoper::compile_lookup(OBJECT symbol, OBJECT var_env);
  };

  std::pair<RelVarScope, size_t> Scoper::compile_lookup(OBJECT symbol, OBJECT var_env) {
    // compile-time type-checks
    bool ok = (
      (var_env.is_pair() && "broken 'env' in compile_lookup: expected pair") &&
      (symbol.is_interned_symbol() && "broken query symbol in compile_lookup: expected symbol")
    );
    if (!ok) {
      throw SsiError();
    }

    // // DEBUG:
    // {
    //     std::cerr 
    //         << "COMPILE_LOOKUP:" << std::endl
    //         << "\t" << symbol << std::endl
    //         << "\t" << var_env << std::endl;
    // }
    
    // checking 'locals'
    {
      OBJECT const all_locals = car(var_env);
      OBJECT locals = all_locals;
      size_t n = 0;
      for (;;) {
        if (locals.is_null()) {
          break;
        }
        if (ss::is_eq(&m_gc_tfe, car(locals), symbol)) {
          return {RelVarScope::Local, n};
        }
        // preparing for the next iteration:
        locals = cdr(locals);
        ++n;
      }
    }

    // checking 'free', trying to get index:
    {
      OBJECT const all_free_vars = cdr(var_env);
      OBJECT free = all_free_vars;
      size_t n = 0;
      
      while (!free.is_null()) {
        if (ss::is_eq(&m_gc_tfe, car(free), symbol)) {
          return {RelVarScope::Free, n};
        }
        // preparing for the next iteration:
        free = cdr(free);
        ++n;
      }
    }
    
    // checking globals
    {
      IntStr sym = symbol.as_interned_symbol();
      auto& gdef_id_symtab = m_code->gdef_id_symtab();
      auto it = gdef_id_symtab.find(sym);
      if (it != gdef_id_symtab.end()) {
        return {RelVarScope::Global, it->second};
      }
    }
    
    // lookup failed:
    {
      std::stringstream ss;
      ss << "Lookup failed: symbol used but not defined: ";
      print_obj(symbol, ss);
      error(ss.str());
      throw SsiError();
    }
  }
  
  OBJECT scope_syntax_impl(OBJECT expr_stx) {
    assert(expr_stx.is_syntax());
  }
}

//
// Impl: macroexpand
//

namespace ss {
  OBJECT macroexpand_syntax_impl(OBJECT expr_stx) {
    OBJECT env = OBJECT::null;
    for (;;) {

    }
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