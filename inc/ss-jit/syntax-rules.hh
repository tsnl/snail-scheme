#pragma once

#include "ss-core/intern.hh"
#include "ss-core/object.hh"

///
// Syntax-rule AST: input to an FSA-compiler
// see p.23 of R7RS-Small
//

namespace ss {

    class Expander;
    class ExpanderEnv;

    // SubPattern
    class SubPattern {
    protected:
        SubPattern() = default;
    public:
        enum class NodeKind {
            Identifier, Constant,
            PatternList,
            PatternVector
        };
    public:
        static SubPattern* parse(Expander* e, ExpanderEnv* env, OBJECT pattern);
    };

    // SubTemplate
    class SubTemplate {
    protected:
        SubTemplate() = default;
    public:
        enum class NodeKind {
            Identifier, Constant,
            List,
            ElementVector
        };
    public:
        static SubTemplate* parse(Expander* e, ExpanderEnv* env, OBJECT pattern);
    };

    // SyntaxRule
    class SyntaxRule {
    private:
        SubPattern* m_pattern;
        SubTemplate* m_template;
    public:
        SyntaxRule(SubPattern* pattern, SubTemplate* template_);
    };

    // SyntaxRules
    class SyntaxRules {
    private:
    public:
        void merge(SyntaxRule syntax_rule);
        void merge(SyntaxRules syntax_rules);
    };

}   // namespace ss
