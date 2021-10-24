#include "printing.hh"

#include <ostream>
#include <iomanip>
#include <cctype>

// #include "object.hh"
#include "intern.hh"
#include "feedback.hh"
#include "object-v2.hh"



void print_obj(Object* obj, std::ostream& out) {
    out << "Removed: print_obj; use print_obj2" << std::endl;
    throw SsiError();
}

// void print_obj(Object* obj, std::ostream& out) {
//     switch (obj_kind(obj)) {
//         case ObjectKind::Null: {
//             out << "()";
//         } break;
//         case ObjectKind::Boolean: {
//             if (static_cast<BoolObject*>(obj)->value()) {
//                 out << "#t";
//             } else {
//                 out << "#f";
//             }
//         } break;
//         case ObjectKind::Integer: {
//             auto int_obj = static_cast<IntObject*>(obj);
//             out << int_obj->value();
//         } break;
//         case ObjectKind::FloatingPt: {
//             auto float_obj = static_cast<FloatObject*>(obj);
//             out << float_obj->value();
//         } break;
//         case ObjectKind::String: {
//             auto str_obj = static_cast<StringObject*>(obj);
//             out << '"';
//             for (size_t i = 0; i < str_obj->count(); i++) {
//                 char cc = str_obj->bytes()[i];
//                 if (cc >= 0) {
//                     switch (cc) {
//                         case '\n': out << "\\n"; break;
//                         case '\r': out << "\\r"; break;
//                         case '\t': out << "\\t"; break;
//                         case '\0': out << "\\0"; break;
//                         case '"': out << "\\\""; break;
//                         default: {
//                             out << cc;
//                         } break;
//                     }
//                 } else {
//                     out << "\\x?";
//                 }
//             }
//             out << '"';
//         } break;
//         case ObjectKind::Symbol: {
//             out << interned_string(static_cast<SymbolObject*>(obj)->name());
//         } break;
//         case ObjectKind::Pair: {
//             auto pair_obj = static_cast<PairObject*>(obj);
//             out << '(';
//             if (pair_obj->cdr() == nullptr) {
//                 // singleton object
//                 print_obj(pair_obj->car(), out);
//             } else {
//                 // (possibly improper) list or pair
//                 if (obj_kind(pair_obj->cdr()) == ObjectKind::Pair) {
//                     // list or improper list
//                     Object* rem_list = pair_obj;
//                     while (rem_list) {
//                         if (obj_kind(rem_list) == ObjectKind::Pair) {
//                             // just a regular list item
//                             auto rem_list_pair = static_cast<PairObject*>(rem_list);
//                             print_obj(rem_list_pair->car(), out);
//                             rem_list = rem_list_pair->cdr();
//                             if (rem_list) {
//                                 out << ' ';
//                             }
//                         } else {
//                             // improper list, with trailing '. <item>'
//                             out << ". ";
//                             print_obj(rem_list, out);
//                             break;
//                         }
//                     }
//                 } else {
//                     // pair
//                     print_obj(pair_obj->car(), out);
//                     out << " . ";
//                     print_obj(pair_obj->cdr(), out);
//                 }
//             }
//             out << ')';
//         } break;
//         case ObjectKind::Vector: {
//             out << "<Vector>";
//         } break;
//         case ObjectKind::Lambda: {
//             out << "<Lambda>";
//         } break;
//         case ObjectKind::VMA_CallFrame: {
//             out << "<VMA_CallFrame>";
//         } break;
//         case ObjectKind::VMA_Closure: {
//             auto closure_obj = static_cast<VMA_ClosureObject*>(obj);
//             out << "(vma-closure ";
//             print_obj(closure_obj->vars(), out);
//             out << " #:vmx " << closure_obj->body()
//                 << " #:env (<...>)";
//             out << ")";
//         } break;
//         case ObjectKind::EXT_Callable: {
//             auto callable_obj = static_cast<EXT_CallableObject*>(obj);
//             out << "(ext-callable ";
//             print_obj(callable_obj->vars(), out);
//             out << " #:env (<...>)";
//             out << ")";
//         }
//     }
// }

void print_obj2(C_word obj, std::ostream& out) {
    //
    // immediate objects:
    //

    if (is_integer(obj)) {
        out << C_UNWRAP_INT(obj);
    }
    else if (is_symbol(obj)) {
        out << interned_string(C_UNWRAP_SYMBOL(obj));
    }
    else if (is_char(obj)) {
        int cc = C_UNWRAP_CHAR(obj);
        switch (cc) {
            case '\n': out << "#\\linefeed" << std::endl; break;
            case '\r': out << "#\\return" << std::endl; break;
            case ' ': out << "#\\space" << std::endl; break;
            default: {
                if (0 < cc) {
                    if (cc < 128 && std::isprint(cc)) {
                        out << "#\\" << static_cast<char>(cc);
                    } else {
                        out << "#\\x" << std::hex << cc << std::dec;
                    }
                }
            }
        }
    }

    //
    // block objects:
    //

    else if (is_flonum(obj)) {
        auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(obj);
        out << std::setprecision(8) << bp->as.flonum;
    }
    else if (is_pair(obj)) {
        auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(obj);
        auto ar = bp->as.pair.ar;
        auto dr = bp->as.pair.dr;
        out << '(';
        if (dr == C_SCHEME_END_OF_LIST) {
            // singleton object/thunk
            print_obj2(ar, out);
        } else {
            // (possibly improper) list or pair
            if (is_pair(dr)) {
                // list or improper list
                C_word rem_list = obj;
                while (rem_list != C_SCHEME_END_OF_LIST) {
                    if (is_pair(rem_list)) {
                        // just a regular list item
                        auto rem_list_bp = reinterpret_cast<C_SCHEME_BLOCK*>(rem_list);
                        auto rem_list_bp_ar = rem_list_bp->as.pair.ar;
                        auto rem_list_bp_dr = rem_list_bp->as.pair.dr;
                        print_obj2(rem_list_bp_ar, out);
                        rem_list = rem_list_bp_dr;
                        if (rem_list != C_SCHEME_END_OF_LIST) {
                            out << ' ';
                        }
                    } else {
                        // improper list, with trailing '. <item>'
                        out << ". ";
                        print_obj2(rem_list, out);
                        break;
                    }
                }
            } else {
                // dotted pair
                print_obj2(ar, out);
                out << " . ";
                print_obj2(dr, out);
            }
        }
        out << ')';
    }
    else if (is_vector(obj)) {
        out << "#(";
        auto length = vector_length(obj);
        for (int64_t i = 0; i < length; i++) {
            print_obj2(vector_ref(obj, i), out);
            if (i+1 != length) {
                out << ' ';
            }
        }
        out << ")";
    }
    else if (is_string(obj)) {
        out << "\"";
        auto length = string_length(obj);
        for (int64_t i = 0; i < length; i++) {
            int cc = string_ref(obj, i);
            // cf: https://www.gnu.org/software/mit-scheme/documentation/stable/mit-scheme-ref/Strings.html
            if (cc == '"') {
                out << "\\\"";
            } else if (cc == '\\') {
                out << "\\\\";
            } else if (std::isprint(cc)) {
                out << static_cast<char>(cc);
            } else {
                out << "\\x" << std::hex << cc << std::dec;
            }
        }
        out << "\"";
    }
    else if (is_procedure(obj)) {
        if (is_closure(obj)) {
            out << "(lambda ";
            print_obj2(c_ref_closure_vars(obj), out);
            out << " "
                << "vmx:" << c_ref_closure_body(obj);
            out << ")";
        } else {
            out << "(native-procedure ";
            print_obj2(c_ref_cpp_callback_args(obj), out);
            out << ")";
        }
    }
    else if (is_eof(obj)) {
        // todo: check if this is right
        out << "#eof";
    }
    else if (is_eol(obj)) {
        out << "'()";
    }
    else if (is_bool(obj)) {
        out << (C_UNWRAP_BOOL(obj) ? "#t" : "#f");
    }
    else if (is_undefined(obj)) {
        out << "(undefined)";
    }

    //
    // error handler
    //

    else {
        // error("NotImplemented: printing an unknown v2 object.");
        // throw SsiError();
        if (obj_kind(obj) == ObjectKind::Broken) {
            out << "(?--broken!!)";
        } else {
            std::stringstream ss;
            ss << "NotImplemented: printing a non-broken object";
            error(ss.str());
            throw SsiError();
        }
    }
}