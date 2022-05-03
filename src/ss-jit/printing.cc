#include "ss-jit/printing.hh"
#include "ss-core/object.hh"
#include "ss-core/intern.hh"
#include "ss-core/feedback.hh"
#include <exception>

namespace ss {

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
                out << interned_string(obj.as_interned_symbol());
            } break;
            case GranularObjectType::Pair: {
                auto pair_obj = obj;
                out << '(';
                if (cdr(pair_obj).is_null()) {
                    // singleton object
                    print_obj(car(pair_obj), out);
                } else {
                    // (possibly improper) list or pair
                    if (cdr(pair_obj).is_pair()) {
                        // list or improper list
                        OBJECT rem_list = pair_obj;
                        while (!rem_list.is_null()) {
                            if (rem_list.is_pair()) {
                                // just a regular list item
                                auto rem_list_pair = dynamic_cast<PairObject*>(rem_list.as_ptr());
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
                        print_obj(car(pair_obj), out);
                        out << " . ";
                        print_obj(cdr(pair_obj), out);
                    }
                }
                out << ')';
            } break;
            case GranularObjectType::Vector: {
                out << "<Vector>";
            } break;
            case GranularObjectType::EXT_Callable: {
                auto callable_obj = static_cast<EXT_CallableObject*>(obj.as_ptr());
                out << "(ext-callable ";
                print_obj(callable_obj->vars(), out);
                out << " #:env (<...>)";
                out << ")";
            } break;
            case GranularObjectType::Box: {
                auto box_obj = static_cast<BoxObject*>(obj.as_ptr());
                out << "(box ";
                print_obj(box_obj->boxed(), out);
                out << ")";
            } break;
            case GranularObjectType::ImmutableVector: {
                error("NotImplemented: support for immutable-vector");
                throw SsiError();
            } break;
        }
    }

}   // namespace ss
