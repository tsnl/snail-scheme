#include "printing.hh"
#include "object.hh"
#include "intern.hh"
#include "feedback.hh"

void print_obj(Object const* obj, std::ostream& out) {
    switch (objkind(obj)) {
        case ObjectKind::Nil: {
            out << "'()";
        } break;
        case ObjectKind::Boolean: {
            if (static_cast<BoolObject const*>(obj)->value()) {
                out << "#t";
            } else {
                out << "#f";
            }
        } break;
        case ObjectKind::Integer: {
            auto int_obj = static_cast<IntObject const*>(obj);
            if (int_obj->value()) {
                out << int_obj->value();
            }
        } break;
        case ObjectKind::FloatingPt: {
            auto float_obj = static_cast<FloatObject const*>(obj);
            if (float_obj->value()) {
                out << float_obj->value();
            }
        } break;
        case ObjectKind::String: {
            auto str_obj = static_cast<StringObject const*>(obj);
            out << '"';
            for (size_t i = 0; i < str_obj->count(); i++) {
                char cc = str_obj->bytes()[i];
                if (cc >= 0) {
                    switch (cc) {
                        case '\n': out << "\\n"; break;
                        case '\r': out << "\\r"; break;
                        case '\t': out << "\\t"; break;
                        case '\0': out << "\\0"; break;
                        case '"': out << "\\\""; break;
                        default: {
                            out << cc;
                        } break;
                    }
                } else {
                    out << "\\x?";
                }
            }
            out << '"';
        } break;
        case ObjectKind::Symbol: {
            out << interned_string(static_cast<SymbolObject const*>(obj)->name());
        } break;
        case ObjectKind::Pair: {
            auto pair_obj = static_cast<PairObject const*>(obj);
            out << '(';
            if (pair_obj->cdr() == nullptr) {
                // singleton object
                print_obj(pair_obj->car(), out);
            } else {
                // (possibly improper) list or pair
                if (pair_obj->cdr()->kind() == ObjectKind::Pair) {
                    // list or improper list
                    Object const* rem_list = pair_obj;
                    while (rem_list) {
                        auto rem_list_pair = static_cast<PairObject const*>(rem_list);
                        if (rem_list_pair) {
                            // just a regular list item
                            print_obj(rem_list_pair->car(), out);
                            rem_list = rem_list_pair->cdr();
                            if (rem_list) {
                                out << ' ';
                            }
                        } else {
                            // improper list, with trailing '. <item>'
                            out << ". ";
                            print_obj(rem_list, out);
                            break;
                        }
                    }
                } else {
                    // pair
                    print_obj(pair_obj->car(), out);
                    out << " . ";
                    print_obj(pair_obj->cdr(), out);
                }
            }
            out << ')';
        } break;
        case ObjectKind::Vector: {
            error("NotImplemented: printing an ObjectKind::Vector");
            throw SsiError();
        } break;
        case ObjectKind::Procedure: {
            error("NotImplemented: printing an ObjectKind::Procedure");
            throw SsiError();
        } break;
    }
}