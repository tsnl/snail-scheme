#include "ss-core/analyst.hh"

#include "ss-core/intern.hh"

namespace ss {

    Analyst::Analyst()
    {}

    void Analyst::check_vars_list_else_throw(FLoc loc, OBJECT vars) {
        OBJECT rem_vars = vars;
        while (!rem_vars.is_null()) {
            OBJECT head = car(rem_vars);
            rem_vars = cdr(rem_vars);

            if (!head.is_symbol()) {
                std::stringstream ss;
                ss << "Invalid variable list for lambda: expected symbol, got: " << head << std::endl;
                ss << "see: " << loc.as_text();
                error(ss.str());
                throw SsiError();
            }
        }
    }

}