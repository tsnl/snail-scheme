#include "ss-jit/syntax-rules.hh"

#include <vector>

#include "ss-jit/expander.hh"

// Common
namespace ss {

    std::pair<OBJECT, OBJECT> next(OBJECT list) {
        return {car(list), cdr(list)};
    };
    
}

// SubPattern
namespace ss {

    // Decl
    //

    class BaseSyntaxPattern: public SubPattern {
    protected:
        NodeKind m_kind;
    protected:
        explicit BaseSyntaxPattern(NodeKind kind);
    };
    
    class IdentifierSyntaxPattern: public BaseSyntaxPattern {
    private:
        IntStr m_name;
    public:
        explicit IdentifierSyntaxPattern(IntStr name);
    };
    
    class ConstantSyntaxPattern: public BaseSyntaxPattern {
    private:
        OBJECT m_constant;
    public:
        explicit ConstantSyntaxPattern(OBJECT constant);
    };

    class BasePatternSequence: public BaseSyntaxPattern {
    public:
        struct Item {
            SubPattern* pattern;
            bool precedes_ellipses;
        public:
            Item(SubPattern* pattern, bool precedes_ellipses)
            :   pattern(pattern),
                precedes_ellipses(precedes_ellipses)
            {}
        };
    protected:
        std::vector<Item> m_items;
    protected:
        BasePatternSequence(NodeKind kind);
    public:
        void append(SubPattern* pattern, bool ellipses);
    };

    class PatternList: public BasePatternSequence {
    private:
        SubPattern* m_opt_improper_tail;
    public:
        PatternList();
    public:
        bool is_improper() const;
        void improper_tail(SubPattern* v);
    };

    // Impl
    //

    class PatternVector: public BasePatternSequence {
    public:
        PatternVector();
    };

    BaseSyntaxPattern::BaseSyntaxPattern(NodeKind kind)
    :   SubPattern(),
        m_kind(kind)
    {}

    IdentifierSyntaxPattern::IdentifierSyntaxPattern(IntStr name)
    :   BaseSyntaxPattern(NodeKind::Identifier), 
        m_name(name) 
    {}

    ConstantSyntaxPattern::ConstantSyntaxPattern(OBJECT constant)
    :   BaseSyntaxPattern(NodeKind::Constant),
        m_constant(constant)
    {}

    BasePatternSequence::BasePatternSequence(NodeKind kind)
    :   BaseSyntaxPattern(kind),
        m_items()
    {}

    void BasePatternSequence::append(SubPattern* pattern, bool ellipses) {
        m_items.emplace_back(pattern, ellipses);
    }

    PatternList::PatternList()
    :   BasePatternSequence(NodeKind::PatternList),
        m_opt_improper_tail(nullptr)
    {}

    bool PatternList::is_improper() const {
        return m_opt_improper_tail != nullptr;
    }
    void PatternList::improper_tail(SubPattern* pattern) {
        assert(pattern != nullptr);
        m_opt_improper_tail = pattern;
    }

    PatternVector::PatternVector()
    :   BasePatternSequence(NodeKind::PatternVector)
    {}

    // Parser
    //

    class PatternParser {
    private:
        Expander* m_expander;
        ExpanderEnv* m_env;
    public:
        explicit PatternParser(Expander* e, ExpanderEnv* env);
    public:
        SubPattern* parse(OBJECT pattern);
        SubPattern* parse_list(OBJECT list);
        SubPattern* parse_vector(OBJECT list);
        SubPattern* parse_constant(OBJECT list);
    };

    PatternParser::PatternParser(Expander* e, ExpanderEnv* env)
    :   m_expander(e),
        m_env(env)
    {}

    SubPattern* PatternParser::parse(OBJECT pattern) {
        if (pattern.is_list()) {
            // list
            return parse_list(pattern);
        } else if (pattern.is_vector()) {
            // vector
            return parse_vector(pattern);
        } else {
            // constant
            return parse_constant(pattern);
        }
    }
    SubPattern* PatternParser::parse_list(OBJECT list) {
        IntStr const ellipses = m_expander->id_cache().ellipses;
        assert(list.is_list());

        auto pattern_vec = new PatternList();
        OBJECT rest = list;
        while (rest.is_pair()) {
            // parsing one pattern:
            auto [item, r0] = next(rest);
            SubPattern* pattern = parse(item);
            rest = r0;

            // checking for postfix ellipses:
            bool postfix_ellipses = false;
            if (rest.is_pair()) {
                auto [item_successor, r0] = next(rest);
                if (item_successor.is_interned_symbol() && item_successor.as_interned_symbol() == ellipses) {
                    // ellipses matched
                    postfix_ellipses = true;
                    rest = r0;
                }
            }

            // appending the node
            pattern_vec->append(pattern, ellipses);
        }
        if (!rest.is_null()) {
            // improper list: must parse 'tail'
            pattern_vec->improper_tail(parse(rest));
        }

        return pattern_vec;
    }

    SubPattern* PatternParser::parse_vector(OBJECT vec) {
        IntStr const ellipses = m_expander->id_cache().ellipses;
        
        assert(vec.is_vector());

        auto pattern_vec = new PatternVector();
        // FIXME: must iterate using a counter: can move 'next' into 'parse_list'
        size_t vec_count = vector_length(vec).as_signed_fixnum();
        for (size_t i = 0; i < vec_count; i++) {
            // parsing one pattern:
            SubPattern* pattern = parse(vector_ref(vec, OBJECT::make_integer(i)));
            
            // checking for postfix ellipses:
            bool postfix_ellipses = false;
            if (i+1 < vec_count) {
                auto item_successor = vector_ref(vec, i+1);
                if (item_successor.is_interned_symbol() && item_successor.as_interned_symbol() == ellipses) {
                    // ellipses matched
                    postfix_ellipses = true;
                    i++;
                }
            }

            // appending the node to the vector:
            pattern_vec->append(pattern, ellipses);
        }

        return pattern_vec;
    }

    SubPattern* PatternParser::parse_constant(OBJECT constant) {
        return new ConstantSyntaxPattern(constant);
    }
    
    SubPattern* SubPattern::parse(Expander* e, ExpanderEnv* env, OBJECT pattern_form) {
        PatternParser parser{e, env};
        return parser.parse(pattern_form);
    }

}

// SubTemplate
namespace ss {

    class TemplateParser {
    private:
        Expander* m_expander;
        ExpanderEnv* m_env;
    public:
        TemplateParser(Expander* expander, ExpanderEnv* env);
    public:
        SubTemplate* parse(OBJECT template_form);
        SubTemplate* parse_literal_form(OBJECT template_form);
        SubTemplate* parse_list(OBJECT template_form);
        SubTemplate* parse_vector(OBJECT template_form);
        SubTemplate* parse_constant(OBJECT template_form);
    };

    TemplateParser::TemplateParser(Expander* expander, ExpanderEnv* env)
    :   m_expander(expander),
        m_env(env)
    {}

    SubTemplate* TemplateParser::parse(OBJECT template_form) {
        IntStr const ellipses = m_expander->id_cache().ellipses;

        if (template_form.is_list()) {
            if (template_form.is_pair()) {
                auto head = car(template_form);
                if (head.is_interned_symbol() && head.as_interned_symbol() == ellipses) {
                    // special (... <template>) form
                    return parse_literal_form(template_form);
                }
            }
            // else, general list form
            return parse_list(template_form);
        } 
        else if (template_form.is_vector()) {
            return parse_vector(template_form);
        }
        else {
            return parse_constant(template_form);
        }
    }

    SubTemplate* SubTemplate::parse(Expander* e, ExpanderEnv* env, OBJECT object) {
        TemplateParser parser{e, env};
        return parser.parse(object);
    }

}
