#include "printing.hh"
#include "object.hh"
#include "intern.hh"
#include "feedback.hh"

void print_obj(Object* obj, std::ostream& out) {
    switch (objkind(obj)) {
        case ObjectKind::Nil: {
            out << "'()";
        } break;
        case ObjectKind::Boolean: {
            if (dynamic_cast<BoolObject*>(obj)->value()) {
                out << "#t";
            } else {
                out << "#f";
            }
        } break;
        case ObjectKind::Integer: {
            auto int_obj = dynamic_cast<IntObject*>(obj);
            if (int_obj->value()) {
                out << int_obj->value();
            }
        } break;
        case ObjectKind::FloatingPt: {
            auto float_obj = dynamic_cast<FloatObject*>(obj);
            if (float_obj->value()) {
                out << float_obj->value();
            }
        } break;
        case ObjectKind::String: {
            auto str_obj = dynamic_cast<StringObject*>(obj);
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
        case ObjectKind::Identifier: {
            out << interned_string(dynamic_cast<IdentifierObject*>(obj)->name());
        } break;
        case ObjectKind::Pair: {
            auto pair_obj = dynamic_cast<PairObject*>(obj);
            out << '(';
            if (!pair_obj->cdr()) {
                print_obj(pair_obj->car(), out);
            } else {
                if (pair_obj->cdr()->kind() == ObjectKind::Pair) {
                    Object* rem_list = pair_obj;
                    while (rem_list) {
                        auto rem_list_pair = dynamic_cast<PairObject*>(rem_list);
                        if (rem_list_pair) {
                            print_obj(rem_list_pair->car(), out);
                            rem_list = rem_list_pair->cdr();

                            if (rem_list) {
                                out << ' ';
                            }
                        } else {
                            error("Invalid list: expected `cdr` to be a pair.");
                            throw SsiError();
                        }
                    }
                } else {
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