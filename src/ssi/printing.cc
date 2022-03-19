#include "printing.hh"
#include "object.hh"
#include "intern.hh"
#include "feedback.hh"
#include <exception>

void print_obj(OBJECT obj, std::ostream& out) {
    switch (obj_kind(obj)) {
        case GranularObjectType::Eof: {
            out << "#\\eof";
        }
        case GranularObjectType::Null: {
            out << "()";
        } break;
        case GranularObjectType::Rune: {
            throw std::runtime_error("NotImplemented: print_obj for GraunlarObjectType::Rune");
        } break;
        case GranularObjectType::Boolean: {
            out << (obj.as_boolean() ? "#t": "#f");
        } break;
        case GranularObjectType::Fixnum: {
            out << obj.as_signed_fixnum();
        } break;
        case GranularObjectType::Float32: {
            out << obj.as_float32();
        } break;
        case GranularObjectType::Float64: {
            out << obj.as_float64();
        } break;
        case GranularObjectType::String: {
            auto str_obj = static_cast<StringObject*>(obj.as_ptr());
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
        case GranularObjectType::InternedSymbol: {
            out << interned_string(static_cast<SymbolObject*>(obj.as_ptr())->name());
        } break;
        case GranularObjectType::Pair: {
            auto pair_obj = static_cast<PairObject*>(obj.as_ptr());
            out << '(';
            if (pair_obj->cdr().is_null()) {
                // singleton object
                print_obj(pair_obj->car(), out);
            } else {
                // (possibly improper) list or pair
                if (obj_kind(pair_obj->cdr()) == GranularObjectType::Pair) {
                    // list or improper list
                    OBJECT rem_list = pair_obj;
                    while (!rem_list.is_null()) {
                        if (obj_kind(rem_list) == GranularObjectType::Pair) {
                            // just a regular list item
                            auto rem_list_pair = static_cast<PairObject*>(rem_list.as_ptr());
                            print_obj(rem_list_pair->car(), out);
                            rem_list = rem_list_pair->cdr();
                            if (!rem_list.is_null()) {
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
        case GranularObjectType::Vector: {
            out << "<Vector>";
        } break;
        case GranularObjectType::VMA_CallFrame: {
            out << "<VMA_CallFrame>";
        } break;
        case GranularObjectType::VMA_Closure: {
            auto closure_obj = static_cast<VMA_ClosureObject*>(obj.as_ptr());
            out << "(vma-closure ";
            print_obj(closure_obj->vars(), out);
            out << " #:vmx " << closure_obj->body()
                << " #:env (<...>)";
            out << ")";
        } break;
        case GranularObjectType::EXT_Callable: {
            auto callable_obj = static_cast<EXT_CallableObject*>(obj.as_ptr());
            out << "(ext-callable ";
            print_obj(callable_obj->vars(), out);
            out << " #:env (<...>)";
            out << ")";
        }
    }
}