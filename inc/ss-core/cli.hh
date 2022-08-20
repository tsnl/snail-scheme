// Support positional args, arity0 flags, and arity1 flags.
// All flags start with '-' and optionally accept a single argument in the next word.
// This suffix string can contain any characters except whitespace.
// E.g.
// ssi 
//  -debug                                              # an arity0 arg, name='debug'
//  -script "./target-script-path.scm"                  # an arity1 arg, name='script'
//  -snlroot "/usr/local/snail-scheme/snlroot/"         # an arity1 arg, name='snlroot'
// NOTE:
// - CAN use '--' to indicate start of only positional arguments
//   => cannot use '-' to begin any flag names, i.e. prefix '--' exclusively separates positional args
// - cannot concatenate multiple flags together with a single '-'
// - cannot specify a flag with a single character abbreviation
// - cannot use `-Dabcdef` syntax for definitions: will produce 'bad flag' error
// - more akin to PowerShell than bash

#pragma once

#include <string>
#include <vector>
#include "ss-core/common.hh"

namespace ss {
    
    using CliArity0Args = UnstableHashMap<std::string, size_t>;
    using CliArity1Args = UnstableHashMap<std::string, std::string>;
    using CliArityNArgs = UnstableHashMap<std::string, std::vector<std::string> >;
    struct CliArgs {
        std::vector<std::string> pos;
        CliArity0Args ar0;
        CliArity1Args ar1;
        CliArityNArgs arN;
    };
    class CliArgsParser {
    private:
        enum class RuleFlag {
            Arity0 = 0x1,
            Arity1 = 0x2,
            CanRepeat = 0x4
        };
        struct ArgRule {
            std::string name;
            size_t rule_flags;
        };
    private:
        std::vector<ArgRule> m_rules;
        bool m_parsed_double_dash_separator;
    public:
        CliArgsParser();
        void reserve_args(size_t count);
        void add_ar0_option_rule(std::string option_name, bool allow_multiple = false);
        void add_ar1_option_rule(std::string option_name, bool allow_multiple = false);
        void add_arN_option_rule(std::string option_name);
        CliArgs parse(int argc, char const* argv[]);
    private:
        void add_generic_option_rule(std::string name, int arity, bool allow_multiple);
        void eat_arg(std::string flag_content, CliArgs& out, int& index, char const* argv[]);
    };

}
