#pragma once

#include <vector>
#include <stack>
#include <string>
#include <stack>
#include <utility>

#include "ss-core/common.hh"
#include "ss-core/object.hh"
#include "ss-jit/analyst.hh"
#include "ss-jit/syntax-rules.hh"

/// Simple phase-based iterative macro expansion that...
// - provides...
//   - `include`, `include-ci` (normalize all to lower-case or upper-case (by argument to `include-ci`), only handle these IDs)
//     - handles recursive expansion, generating an error on cyclic expansion
//   - `cond-expand` can be resolved using `eval` to perform single-shot compilation and execution with an anonymous VM.
//     - initially implemented as only `test`, gives us time until partial evaluation pass
//     - a 'template program' can be used to splice `cond-expand` conditions into a regular `cond`/`if` expression that returns
//       a 'branch selector' integer as the script output (see 'a' register). Compiler can be configured with built-in constants.
//   - define-syntax, expansion of user-defined macros
//   - lines classified by purpose: macro, library-spec, or value-{def, eval}

namespace ss {

    class ExpanderEnv {
    private:
        using Scope = UnstableHashMap<IntStr, SyntaxRules>;
        std::stack<Scope> m_scope_stack;
    };

    class Expander: public Analyst {
    private:
        struct MacroInfo {
            // TODO: implement me
        };
        using SymbolTable = UnstableHashMap<IntStr, MacroInfo>;
        struct WorkingSet {
            std::string const& includer_cwd;
            std::vector<OBJECT> input_lines;
            std::vector<OBJECT> output_lines;
            std::stack<SymbolTable> scopes;
            size_t iter_count;

            explicit WorkingSet(std::string const& includer_cwd)
            :   includer_cwd(includer_cwd),
                input_lines(),
                output_lines(),
                scopes(),
                iter_count()
            {}
        };
    private:
        std::string m_root_abspath;
        UnstableHashMap< std::string, std::vector<OBJECT> > m_cached_input_map;
    public:
        explicit Expander(std::string project_root_abspath);
    public:
        std::vector<OBJECT> expand_lines(std::string const& includer_cwd, std::vector<OBJECT> lines);
    private:
        bool expand_iter(WorkingSet& ws);
    public:
        std::string resolve_include_path(std::string const& includer_cwd, std::string include_path);
        OBJECT expand_line(OBJECT o, ExpanderEnv* env);
    };
    
}

///
// Inline function definitions:
//

namespace ss {
    Expander::Expander(std::string project_root_abspath)
    :   m_root_abspath(std::move(project_root_abspath)),
        m_cached_input_map()
    {}
}