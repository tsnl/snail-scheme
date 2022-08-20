#include "ss-core/cli.hh"

#include <string>
#include <string_view>
#include <sstream>
#include <cassert>

#include "ss-core/feedback.hh"

namespace ss {

    void throw_bad_rule_error(std::string flag_prefix, std::string more) {
        std::stringstream ss;
        ss << "(Implementation error) cannot add invalid command-line rule: " << flag_prefix << ": " << more;
        error(ss.str());
        throw SsiError();
    }
    void throw_repetition_error(std::string s) {
        std::stringstream ss;
        ss << "Cannot repeat command-line arg '" << s << "': it can only occur once.";
        error(ss.str());
        throw SsiError();
    }
    void throw_syntax_error(std::string s) {
        std::stringstream ss;
        ss << "Syntax error in command-line arg: " << s;
        error(ss.str());
        throw SsiError();
    }
    void throw_bad_opt_arg_error(std::string arg_name, std::string more) {
        std::stringstream ss;
        ss << "Bad optional command-line argument: -" << arg_name << ": " << more;
        error(ss.str());
        throw SsiError();
    }

    CliArgsParser::CliArgsParser()
    :   m_rules(),
        m_parsed_double_dash_separator(false)
    {}

    void CliArgsParser::reserve_args(size_t count) {
        m_rules.reserve(count);
    }

    void CliArgsParser::add_ar0_option_rule(std::string option_name, bool allow_multiple) {
        add_generic_option_rule(std::move(option_name), 0, allow_multiple);
    }
    void CliArgsParser::add_ar1_option_rule(std::string option_name, bool allow_multiple) {
        add_generic_option_rule(std::move(option_name), 1, allow_multiple);
    }
    void CliArgsParser::add_arN_option_rule(std::string option_name) {
        // NOTE: arity arg is either '0', '1', or ANY OTHER VALUE (for 'N')
        add_generic_option_rule(std::move(option_name), 2, true);
    }
    void CliArgsParser::add_generic_option_rule(std::string name, int arity, bool allow_multiple) {
        // NOTE: arity arg is either '0', '1', or ANY OTHER VALUE (for 'N')
        
        // checking:
        if (name[0] == '-') {
            throw_bad_rule_error(std::move(name), "no flag name can begin with '-': its prefix would be '--' and this is a reserved token.");
        }
        for (auto const& existing_rule: m_rules) {
            if (existing_rule.name == name) {
                throw_bad_rule_error(std::move(name), "rule re-defined");
            }
        }
        
        // pushing:
        size_t flags = (
            (arity == 0     ? static_cast<size_t>(RuleFlag::Arity0)    : 0) |
            (arity == 1     ? static_cast<size_t>(RuleFlag::Arity1)    : 0) |
            (allow_multiple ? static_cast<size_t>(RuleFlag::CanRepeat) : 0)
        );
        ArgRule rule {std::move(name), flags};
        m_rules.push_back(std::move(rule));
    }

    CliArgs CliArgsParser::parse(int argc, char const* argv[]) {
        CliArgs out_args;
        for (int i = 1; i < argc; i++) {
            char const* s = argv[i];
            if (!m_parsed_double_dash_separator && (s[0] == '-' && s[1] == '-')) {
                // '--' separator
                if (s[2] != '\0') {
                    throw_syntax_error("cannot include any characters after '--' (use '-flag' for all flags, a space separator for posarg)");
                }
                if (m_parsed_double_dash_separator) {
                    throw_repetition_error("--");
                } else {
                    m_parsed_double_dash_separator = true;
                }
            }
            else if (!m_parsed_double_dash_separator && s[0] == '-') {
                // flag
                std::string flag_content = s+1;
                eat_arg(flag_content, out_args, i, argv);
            }
            else {
                // positional
                out_args.pos.emplace_back(s);
            }
        }
        return out_args;
    }

    void CliArgsParser::eat_arg(std::string flag_content, CliArgs& out, int& index, char const* argv[]) {
        size_t max_match_index = m_rules.size();
        for (size_t rule_index = 0; rule_index < m_rules.size(); rule_index++) {
            ArgRule const& rule = m_rules[rule_index];
            if (flag_content == rule.name) {
                max_match_index = rule_index;
                break;
            }
        }
        if (max_match_index == m_rules.size()) {
            throw_bad_opt_arg_error(flag_content, "no matching optional rule is defined");    
        }
        else {
            assert(max_match_index < m_rules.size());
            std::string key = m_rules[max_match_index].name;
            size_t flags = m_rules[max_match_index].rule_flags;
            bool arity0 = flags & static_cast<size_t>(RuleFlag::Arity0);
            bool arity1 = flags & static_cast<size_t>(RuleFlag::Arity1);
            bool can_repeat = flags & static_cast<size_t>(RuleFlag::CanRepeat);;
            if (arity0) {
                // ar0
                if (!out.ar0.contains(key)) {
                    out.ar0[key] = 1;
                } else if (can_repeat) {
                    ++out.ar0[key];
                } else {
                    throw_bad_opt_arg_error(key, "cannot repeat this flag");
                }
            }
            else if (arity1) {
                // ar1
                int val_index = ++index;
                std::string val = argv[val_index];
                if (!out.ar1.contains(key) || can_repeat) {
                    out.ar1[key] = std::move(val);
                } else {
                    throw_bad_opt_arg_error(key, "multiple values provided for the same unique optional argument");
                }
            } 
            else {
                // arN
                int val_index = ++index;
                std::string val = argv[val_index];
                if (!out.arN.contains(key)) {
                    std::vector<std::string> first_vec;
                    first_vec.reserve(1);
                    first_vec.push_back(std::move(val));
                    out.arN[key] = std::move(first_vec);
                } else if (can_repeat) {
                    out.arN[key].push_back(std::move(val));
                } else {
                    throw_bad_opt_arg_error(key, "multiple values provided for the same unique optional argument");
                }
            }
        }
    }

}