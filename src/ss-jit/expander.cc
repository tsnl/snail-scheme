#include "ss-jit/expander.hh"

#include <string>
#include "ss-core/feedback.hh"
#include "ss-core/object.hh"

///
// Interface:
//

namespace ss {

    std::vector<OBJECT> Expander::expand_lines(std::string const& includer_cwd, std::vector<OBJECT> lines) {
        // iterating until we hit a maximum phase-level or until we reach a fixed-point:
        size_t const max_iter_count = 5000;
        WorkingSet ws{includer_cwd};
        ws.input_lines = std::move(lines);
        ws.output_lines.reserve(ws.input_lines.size());
        ws.iter_count = 0;
        // TODO: initialize ws.scopes with globals
        while (ws.iter_count < max_iter_count) {
            bool is_fixed = expand_iter(ws);
            if (is_fixed) {
                break;
            } else {
                ws.input_lines = std::move(ws.output_lines);
                ws.output_lines.reserve(ws.input_lines.size());
                ws.iter_count++;
            }
        }
        return std::move(ws.output_lines);
    }
    bool Expander::expand_iter(WorkingSet& ws) {
        bool is_fixed = true;
        ExpanderEnv env;
        for (OBJECT input_line: ws.input_lines) {
            OBJECT output_line = expand_line(input_line, &env);
        }
        return is_fixed;
    }
    std::string Expander::resolve_include_path(std::string const& includer_cwd, std::string include_path) {
        if (include_path[0] == '$') {
            return m_root_abspath + "/" + include_path.substr(1);
        } else if (include_path[0] == '.' && include_path[1] == '/') {
            return includer_cwd + "/" + include_path.substr(2);
        } else {
            std::stringstream ss;
            ss  << "Invalid path specified to `include` or `include-ci`: " << include_path << std::endl
                << "HINT: Expected include path to start with either `./` (relative to includer) or `$/` (relative to project root)";
            error(ss.str());
            throw SsiError();
        }
    }

}