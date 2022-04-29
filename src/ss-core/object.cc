#include "ss-core/object.hh"

#include <map>
#include <exception>

#include <cstring>
#include <cassert>

#include "ss-jit/printing.hh"
#include "ss-core/gc.hh"

namespace ss {

    ///
    // OBJECT::*
    //

    const OBJECT OBJECT::null{make_null()};
    const OBJECT OBJECT::undef{make_undef()};
    const OBJECT OBJECT::eof{make_eof()};
    const OBJECT OBJECT::s_boolean_t{true};
    const OBJECT OBJECT::s_boolean_f{false};

    constexpr gc::SizeClassIndex float64_sci = gc::sci(sizeof(Float64Object));
    constexpr gc::SizeClassIndex pair_sci = gc::sci(sizeof(PairObject));
    constexpr gc::SizeClassIndex string_sci = gc::sci(sizeof(StringObject));
    constexpr gc::SizeClassIndex box_sci = gc::sci(sizeof(BoxObject));
    const gc::SizeClassIndex VectorObject::sci = gc::sci(sizeof(VectorObject));


    OBJECT OBJECT::make_float64(GcThreadFrontEnd* gc_tfe, double f64) {
        auto boxed_object = new (gc_tfe, float64_sci) Float64Object(f64);
        return OBJECT::make_generic_boxed(boxed_object);
    }
    OBJECT OBJECT::make_box(GcThreadFrontEnd* gc_tfe, OBJECT stored) {
        auto boxed_object = new(gc_tfe, box_sci) BoxObject(stored);
        return OBJECT::make_generic_boxed(boxed_object);
    }
    OBJECT OBJECT::make_pair(GcThreadFrontEnd* gc_tfe, OBJECT head, OBJECT tail) {
        auto boxed_object = new (gc_tfe, pair_sci) PairObject(head, tail);
        return OBJECT::make_generic_boxed(boxed_object);
    }
    OBJECT OBJECT::make_string(GcThreadFrontEnd* gc_tfe, size_t byte_count, char* mv_bytes, bool collect_bytes) {
        auto boxed_object = new (gc_tfe, string_sci) StringObject(byte_count, mv_bytes);
        return OBJECT::make_generic_boxed(boxed_object);
    }

    ///
    // equivalence predicates:
    // https://groups.csail.mit.edu/mac/ftpdir/scheme-7.4/doc-html/scheme_4.html
    //

    bool is_eqn(OBJECT e1, OBJECT e2) {
        auto v1 = e1.to_double();
        auto v2 = e2.to_double();
        return v1 == v2;
    }
    bool is_eq(GcThreadFrontEnd* gc_tfe, OBJECT e1, OBJECT e2) {
        return e1.as_raw() == e2.as_raw();
    }
    bool is_eqv(GcThreadFrontEnd* gc_tfe, OBJECT e1, OBJECT e2) {
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
                    return is_eq(gc_tfe, e1, e2);
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
                        is_eq(gc_tfe, p1->car(), p2->car()) &&
                        is_eq(gc_tfe, p1->cdr(), p2->cdr());
                }
                case GranularObjectType::Vector: {
                    auto v1 = static_cast<VectorObject*>(e1.as_ptr());
                    auto v2 = static_cast<VectorObject*>(e2.as_ptr());
                    return 
                        v1->count() == v2->count() &&
                        v1->array() == v2->array();
                }
                default: {
                    std::stringstream ss;
                    ss << "eqv?: invalid arguments: ";
                    print_obj(list(gc_tfe, e1, e2), ss);
                    error(ss.str());
                    throw SsiError();
                }
            }
        }
    }
    bool is_equal(GcThreadFrontEnd* gc_tfe, OBJECT e1, OBJECT e2) {
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
                    return is_eqv(gc_tfe, e1, e2);
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
                        is_equal(gc_tfe, p1->car(), p2->car()) &&
                        is_equal(gc_tfe, p1->cdr(), p2->cdr());
                }
                case GranularObjectType::Vector: {
                    auto v1 = static_cast<VectorObject*>(e1.as_ptr());
                    auto v2 = static_cast<VectorObject*>(e2.as_ptr());
                    
                    if (v1->count() == v2->count()) {
                        size_t count = v1->count();
                        for (size_t i = 0; i < count; i++) {
                            if (!is_equal(gc_tfe, v1->array()[i], v2->array()[i])) {
                                return false;
                            }
                        }
                        return true;
                    } else {
                        return false;
                    }
                }
                default: {
                    std::stringstream ss;
                    ss << "eqv?: invalid arguments: ";
                    print_obj(list(gc_tfe, e1, e2), ss);
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

    ///
    // BaseBoxedObject
    //

    void* BaseBoxedObject::operator new(size_t allocation_size, void* placement_ptr) {
        return placement_ptr;
    }
    void* BaseBoxedObject::operator new(size_t alloc_size, GcThreadFrontEnd* gc_tfe, gc::SizeClassIndex sci) {
        return reinterpret_cast<APtr>(gc_tfe->allocate_size_class(sci));
    }
    void BaseBoxedObject::operator delete(void* ptr, GcThreadFrontEnd* gc_tfe, gc::SizeClassIndex sci) {
        auto self = static_cast<BaseBoxedObject*>(ptr);
#if CONFIG_DEBUG_MODE
        assert(self->m_sci == sci && "SCI corruption detected");
        assert(GcThreadFrontEnd::get_by_tfid(self->m_gc_tfid) == gc_tfe && "GC_TFE corruption detected");
#endif
        BaseBoxedObject::operator delete(ptr);
    }
    void BaseBoxedObject::operator delete(void* ptr) {
        BaseBoxedObject* p = static_cast<BaseBoxedObject*>(ptr);
        p->delete_();
    }
    void BaseBoxedObject::operator delete(void* ptr, size_t size_in_bytes) {
        auto self = static_cast<BaseBoxedObject*>(ptr);
#if CONFIG_DEBUG_MODE
        assert(gc::sci(size_in_bytes) == self->m_sci && "SCI corruption detected");
#endif
        BaseBoxedObject::operator delete(ptr);
    }
    void BaseBoxedObject::delete_() {
        return GcThreadFrontEnd::get_by_tfid(m_gc_tfid)->deallocate_size_class(reinterpret_cast<APtr>(this), m_sci);
    }

}   // namespace ss
