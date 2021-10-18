#include "object.hh"

#include <map>
#include <cstring>

#include "printing.hh"

//std::map<Object*, ObjectKind> Object::s_non_nil_object_kind_map{};
BoolObject BoolObject::t_storage{true};
BoolObject BoolObject::f_storage{false};
BoolObject* BoolObject::t{&BoolObject::t_storage};
BoolObject* BoolObject::f{&BoolObject::f_storage};

// equivalence predicates:
// https://groups.csail.mit.edu/mac/ftpdir/scheme-7.4/doc-html/scheme_4.html

bool is_eqn(Object* e1, Object* e2) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    bool types_ok = (
        e1->kind() == ObjectKind::Integer && e2->kind() == ObjectKind::Integer ||
        e1->kind() == ObjectKind::FloatingPt && e2->kind() == ObjectKind::FloatingPt
    );
    if (!types_ok) {
        std::stringstream ss;
        ss << "= operator: invalid arguments: ";
        print_obj(list(e1, e2), ss);
        error(ss.str());
        throw SsiError();
    }
#endif

    // kind-independent bit-based check:
    return 0 == memcmp(
        static_cast<BaseNumberObject*>(e1)->mem(),
        static_cast<BaseNumberObject*>(e2)->mem(),
        sizeof(NumberObjectMemory)
    );
}
bool is_eq(Object* e1, Object* e2) {
    return e1 == e2;
}
bool is_eqv(Object* e1, Object* e2) {
    if (!e1 && !e2) {
        // null == null
        return true;
    }
    else if (!e1 || !e2) {
        // null != anything else
        return false;
    } 
    else {
        // e1 != null, e2 != null
        switch (e1->kind()) {
            case ObjectKind::Boolean: {
                return is_eq(e1, e2);
            }
            case ObjectKind::Symbol: {
                return (
                    static_cast<SymbolObject*>(e1)->name() == 
                    static_cast<SymbolObject*>(e2)->name()
                );
            }
            case ObjectKind::String: {
                auto s1 = static_cast<StringObject*>(e1);
                auto s2 = static_cast<StringObject*>(e2);
                return (
                    (s1->count() == s2->count()) && 
                    (0 == strcmp(s1->bytes(), s2->bytes()))
                );
            }
            case ObjectKind::Integer: 
            case ObjectKind::FloatingPt:
            {
                // kind-independent bit-based check:
                return 0 == memcmp(
                    static_cast<BaseNumberObject*>(e1)->mem(),
                    static_cast<BaseNumberObject*>(e2)->mem(),
                    sizeof(NumberObjectMemory)
                );
            }
            case ObjectKind::Pair: {
                auto p1 = static_cast<PairObject*>(e1);
                auto p2 = static_cast<PairObject*>(e2);
                return 
                    p1->car() == p2->car() &&
                    p1->cdr() == p2->cdr();
            }
            case ObjectKind::Vector: {
                auto v1 = static_cast<VectorObject*>(e1);
                auto v2 = static_cast<VectorObject*>(e2);
                return 
                    v1->count() == v2->count() &&
                    v1->array() == v2->array();
            }
            case ObjectKind::VMA_Closure: {
                auto c1 = static_cast<VMA_ClosureObject*>(e1);
                auto c2 = static_cast<VMA_ClosureObject*>(e2);
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
bool is_equal(Object* e1, Object* e2) {
    if (!e1 && !e2) {
        // null == null
        return true;
    }
    else if (!e1 || !e2) {
        // null != anything else
        return false;
    } 
    else {
        // e1 != null, e2 != null
        switch (e1->kind()) {
            case ObjectKind::Boolean: {
                return is_eq(e1, e2);
            }
            case ObjectKind::Symbol: {
                return (
                    static_cast<SymbolObject*>(e1)->name() == 
                    static_cast<SymbolObject*>(e2)->name()
                );
            }
            case ObjectKind::String: {
                auto s1 = static_cast<StringObject*>(e1);
                auto s2 = static_cast<StringObject*>(e2);
                return (
                    (s1->count() == s2->count()) && 
                    (s1->bytes() == s2->bytes())
                );
            }
            case ObjectKind::Integer: 
            case ObjectKind::FloatingPt:
            {
                // kind-independent bit-based check:
                return 0 == memcmp(
                    static_cast<BaseNumberObject*>(e1)->mem(),
                    static_cast<BaseNumberObject*>(e2)->mem(),
                    sizeof(NumberObjectMemory)
                );
            }
            case ObjectKind::Pair: {
                auto p1 = static_cast<PairObject*>(e1);
                auto p2 = static_cast<PairObject*>(e2);
                return 
                    is_equal(p1->car(), p2->car()) &&
                    is_equal(p1->cdr(), p2->cdr());
            }
            case ObjectKind::Vector: {
                auto v1 = static_cast<VectorObject*>(e1);
                auto v2 = static_cast<VectorObject*>(e2);
                return 
                    v1->count() == v2->count() &&
                    0 == memcmp(v1->array(), v2->array(), v1->count() * sizeof(Object*));
            }
            case ObjectKind::VMA_Closure: {
                auto c1 = static_cast<VMA_ClosureObject*>(e1);
                auto c2 = static_cast<VMA_ClosureObject*>(e2);
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