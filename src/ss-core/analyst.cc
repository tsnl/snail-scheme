#include "ss-core/analyst.hh"

#include "ss-core/intern.hh"

namespace ss {

    Analyst::Analyst()
    {}

    void Analyst::check_vars_list_else_throw(OBJECT vars) {
        OBJECT rem_vars = vars;
        while (!rem_vars.is_null()) {
            OBJECT head = car(rem_vars);
            rem_vars = cdr(rem_vars);

            if (!head.is_interned_symbol()) {
                std::stringstream ss;
                ss << "Invalid variable list for lambda: expected symbol, got: " << head;
                ss << std::endl;
                error(ss.str());
                throw SsiError();
            }
        }
    }

}