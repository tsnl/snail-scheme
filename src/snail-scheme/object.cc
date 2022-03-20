#include "snail-scheme/object.hh"

#include <map>
#include <cstring>
#include <exception>

#include "snail-scheme/printing.hh"

OBJECT OBJECT::s_boolean_t{true};
OBJECT OBJECT::s_boolean_f{false};

// equivalence predicates:
// https://groups.csail.mit.edu/mac/ftpdir/scheme-7.4/doc-html/scheme_4.html

bool is_eqn(OBJECT e1, OBJECT e2) {
    auto v1 = e1.to_double();
    auto v2 = e2.to_double();
    return v1 == v2;
}
bool is_eq(OBJECT e1, OBJECT e2) {
    return e1.as_raw() == e2.as_raw();
}
bool is_eqv(OBJECT e1, OBJECT e2) {
    GranularObjectType e1_kind = e1.kind();
    GranularObjectType e2_kind = e2.kind();
    if (e1_kind != e2_kind) {
        return false;
    } else {
        // e1 != null, e2 != null
        switch (e1_kind) {
            case GranularObjectType::Null:
            case GranularObjectType::Eof:
            case GranularObjectType::Rune:
            case GranularObjectType::Boolean: 
            case GranularObjectType::Fixnum:
            {
                return is_eq(e1, e2);
            }
            case GranularObjectType::Float32:
            {
                return e1.as_float32() == e2.as_float32();
            }
            case GranularObjectType::InternedSymbol: {
                return e1.as_interned_symbol() == e2.as_interned_symbol();
            }
            case GranularObjectType::String: {
                auto s1 = static_cast<StringObject*>(e1.as_ptr());
                auto s2 = static_cast<StringObject*>(e2.as_ptr());
                return (
                    (s1->count() == s2->count()) && 
                    (0 == strcmp(s1->bytes(), s2->bytes()))
                );
            }
             
            case GranularObjectType::Float64:
            {
                // kind-independent bit-based check:
                return e1.as_float64() == e2.as_float64();
            }
            case GranularObjectType::Pair: {
                auto p1 = static_cast<PairObject*>(e1.as_ptr());
                auto p2 = static_cast<PairObject*>(e2.as_ptr());
                return 
                    is_eq(p1->car(), p2->car()) &&
                    is_eq(p1->cdr(), p2->cdr());
            }
            case GranularObjectType::Vector: {
                auto v1 = static_cast<VectorObject*>(e1.as_ptr());
                auto v2 = static_cast<VectorObject*>(e2.as_ptr());
                return 
                    v1->count() == v2->count() &&
                    v1->array() == v2->array();
            }
            case GranularObjectType::VMA_Closure: {
                auto c1 = static_cast<VMA_ClosureObject*>(e1.as_ptr());
                auto c2 = static_cast<VMA_ClosureObject*>(e2.as_ptr());
                return c1->body() == c2->body();
            }
            default: {
                std::stringstream ss;
                ss << "eqv?: invalid arguments: ";
                print_obj(list(e1, e2), ss);
                error(ss.str());
                throw SsiError();
            }
        }
    }
}
bool is_equal(OBJECT e1, OBJECT e2) {
    auto e1_kind = e1.kind();
    auto e2_kind = e2.kind();

    if (e1_kind != e2_kind) {
        return false;
    } else {
        // e1 != null, e2 != null
        switch (e1_kind) {
            case GranularObjectType::Boolean:
            case GranularObjectType::Fixnum:
            case GranularObjectType::Float32:
            case GranularObjectType::Float64:
            {
                return is_eqv(e1, e2);
            }
            case GranularObjectType::InternedSymbol: {
                return e1.as_interned_symbol() == e2.as_interned_symbol();
            }
            case GranularObjectType::String: {
                auto s1 = static_cast<StringObject*>(e1.as_ptr());
                auto s2 = static_cast<StringObject*>(e2.as_ptr());
                return (
                    (s1->count() == s2->count()) && 
                    (s1->bytes() == s2->bytes())
                );
            }
            case GranularObjectType::Pair: {
                auto p1 = static_cast<PairObject*>(e1.as_ptr());
                auto p2 = static_cast<PairObject*>(e2.as_ptr());
                return 
                    is_equal(p1->car(), p2->car()) &&
                    is_equal(p1->cdr(), p2->cdr());
            }
            case GranularObjectType::Vector: {
                auto v1 = static_cast<VectorObject*>(e1.as_ptr());
                auto v2 = static_cast<VectorObject*>(e2.as_ptr());
                
                if (v1->count() == v2->count()) {
                    size_t count = v1->count();
                    for (size_t i = 0; i < count; i++) {
                        if (!is_equal(v1->array()[i], v2->array()[i])) {
                            return false;
                        }
                    }
                    return true;
                } else {
                    return false;
                }
            }
            case GranularObjectType::VMA_Closure: {
                auto c1 = static_cast<VMA_ClosureObject*>(e1.as_ptr());
                auto c2 = static_cast<VMA_ClosureObject*>(e2.as_ptr());
                return c1->body() == c2->body();
            }
            default: {
                std::stringstream ss;
                ss << "eqv?: invalid arguments: ";
                print_obj(list(e1, e2), ss);
                error(ss.str());
                throw SsiError();
            }
        }
    }
}

std::ostream& operator<<(std::ostream& out, const OBJECT& obj) {
    print_obj(obj, out);
    return out;
}