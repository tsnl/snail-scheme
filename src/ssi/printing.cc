#include "printing.hh"
#include "object.hh"
#include "intern.hh"
#include "feedback.hh"

void print_obj(Object* obj, std::ostream& out) {
    switch (obj_kind(obj)) {
        case ObjectKind::Null: {
            out << "()";
        } break;
        case ObjectKind::Boolean: {
            if (static_cast<BoolObject*>(obj)->value()) {
                out << "#t";
            } else {
                out << "#f";
            }
        } break;
        case ObjectKind::Integer: {
            auto int_obj = static_cast<IntObject*>(obj);
            out << int_obj->value();
        } break;
        case ObjectKind::FloatingPt: {
            auto float_obj = static_cast<FloatObject*>(obj);
            out << float_obj->value();
        } break;
        case ObjectKind::String: {
            auto str_obj = static_cast<StringObject*>(obj);
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
            out << interned_string(static_cast<SymbolObject*>(obj)->name());
        } break;
        case ObjectKind::Pair: {
            auto pair_obj = static_cast<PairObject*>(obj);
            out << '(';
            if (pair_obj->cdr() == nullptr) {
                // singleton object
                print_obj(pair_obj->car(), out);
            } else {
                // (possibly improper) list or pair
                if (obj_kind(pair_obj->cdr()) == ObjectKind::Pair) {
                    // list or improper list
                    Object* rem_list = pair_obj;
                    while (rem_list) {
                        if (obj_kind(rem_list) == ObjectKind::Pair) {
                            // just a regular list item
                            auto rem_list_pair = static_cast<PairObject*>(rem_list);
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
            out << "<Vector>";
        } break;
        case ObjectKind::Lambda: {
            out << "<Lambda>";
        } break;
        case ObjectKind::VMA_CallFrame: {
            out << "<VMA_CallFrame>";
        } break;
        case ObjectKind::VMA_Closure: {
            auto closure_obj = static_cast<VMA_ClosureObject*>(obj);
            out << "(vma-closure ";
            print_obj(closure_obj->vars(), out);
            out << " #:vmx " << closure_obj->body()
                << " #:env (<...>)";
            out << ")";
        } break;
        case ObjectKind::EXT_Callable: {
            auto callable_obj = static_cast<EXT_CallableObject*>(obj);
            out << "(ext-callable ";
            print_obj(callable_obj->vars(), out);
            out << " #:env (<...>)";
            out << ")";
        }
    }
}