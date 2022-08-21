#include "ss-core/object.hh"

#include <map>
#include <exception>

#include <cstring>
#include <cassert>

#include "ss-core/common.hh"
#include "ss-core/printing.hh"
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
    const gc::SizeClassIndex SyntaxObject::sci = gc::sci(sizeof(SyntaxObject));

    OBJECT OBJECT::make_float64(GcThreadFrontEnd* gc_tfe, double f64) {
        auto boxed_object = new (gc_tfe, float64_sci) Float64Object(f64);
        return OBJECT::make_ptr(boxed_object);
    }
    OBJECT OBJECT::make_box(GcThreadFrontEnd* gc_tfe, OBJECT stored) {
        auto boxed_object = new(gc_tfe, box_sci) BoxObject(stored);
        return OBJECT::make_ptr(boxed_object);
    }
    OBJECT OBJECT::make_pair(GcThreadFrontEnd* gc_tfe, OBJECT head, OBJECT tail) {
        auto boxed_object = new (gc_tfe, pair_sci) PairObject(head, tail);
        return OBJECT::make_ptr(boxed_object);
    }
    OBJECT OBJECT::make_string(GcThreadFrontEnd* gc_tfe, size_t byte_count, char* mv_bytes, bool collect_bytes) {
        auto boxed_object = new (gc_tfe, string_sci) StringObject(byte_count, mv_bytes, collect_bytes);
        return OBJECT::make_ptr(boxed_object);
    }
    OBJECT OBJECT::make_vector(GcThreadFrontEnd* gc_tfe, std::vector<OBJECT> raw) {
        auto ptr = new(gc_tfe, VectorObject::sci) VectorObject(std::move(raw));
        return OBJECT::make_ptr(ptr);
    }
    OBJECT OBJECT::make_syntax(GcThreadFrontEnd* gc_tfe, OBJECT data, FLoc loc) {
        auto ptr = new(gc_tfe, SyntaxObject::sci) SyntaxObject{data, loc};
        return OBJECT::make_ptr(ptr);
    }

    bool OBJECT::is_atom() const {
        return 0
        || is_null()
        || is_boolean()
        || is_string() 
        || is_integer()
        || is_float32()
        || is_float64()
        || is_symbol();
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
    bool is_eq(OBJECT e1, OBJECT e2) {
        return e1.as_raw() == e2.as_raw();
    }
    bool is_eqv(GcThreadFrontEnd* gc_tfe, OBJECT e1, OBJECT e2) {
        ObjectKind e1_kind = e1.kind();
        ObjectKind e2_kind = e2.kind();
        if (e1_kind != e2_kind) {
            return false;
        } else {
            // e1 != null, e2 != null
            switch (e1_kind) {
                case ObjectKind::Null:
                case ObjectKind::Eof:
                case ObjectKind::Rune:
                case ObjectKind::Boolean: 
                case ObjectKind::Fixnum:
                {
                    return is_eq(e1, e2);
                }
                case ObjectKind::Float32:
                {
                    return e1.as_float32() == e2.as_float32();
                }
                case ObjectKind::InternedSymbol: {
                    return e1.as_symbol() == e2.as_symbol();
                }
                case ObjectKind::String: {
                    auto s1 = static_cast<StringObject*>(e1.as_ptr());
                    auto s2 = static_cast<StringObject*>(e2.as_ptr());
                    return (
                        (s1->count() == s2->count()) && 
                        (0 == strcmp(s1->bytes(), s2->bytes()))
                    );
                }
                
                case ObjectKind::Float64:
                {
                    // kind-independent bit-based check:
                    return e1.as_float64() == e2.as_float64();
                }
                case ObjectKind::Pair: {
                    auto p1 = e1.as_pair_p();
                    auto p2 = e2.as_pair_p();
                    return 
                        is_eq(p1->car(), p2->car()) &&
                        is_eq(p1->cdr(), p2->cdr());
                }
                case ObjectKind::Vector: {
                    auto v1 = e1.as_vector_p();
                    auto v2 = e2.as_vector_p();
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
                case ObjectKind::Boolean:
                case ObjectKind::Fixnum:
                case ObjectKind::Float32:
                case ObjectKind::Float64:
                {
                    return is_eqv(gc_tfe, e1, e2);
                }
                case ObjectKind::InternedSymbol: {
                    return e1.as_symbol() == e2.as_symbol();
                }
                case ObjectKind::String: {
                    auto s1 = static_cast<StringObject*>(e1.as_ptr());
                    auto s2 = static_cast<StringObject*>(e2.as_ptr());
                    return (
                        (s1->count() == s2->count()) && 
                        (s1->bytes() == s2->bytes())
                    );
                }
                case ObjectKind::Pair: {
                    auto p1 = e1.as_pair_p();
                    auto p2 = e2.as_pair_p();
                    return 
                        is_equal(gc_tfe, p1->car(), p2->car()) &&
                        is_equal(gc_tfe, p1->cdr(), p2->cdr());
                }
                case ObjectKind::Vector: {
                    auto v1 = e1.as_vector_p();
                    auto v2 = e2.as_vector_p();
                    
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
        SUPPRESS_UNUSED_VARIABLE_WARNING(allocation_size);
        return placement_ptr;
    }
    void* BaseBoxedObject::operator new(size_t alloc_size, GcThreadFrontEnd* gc_tfe, gc::SizeClassIndex sci) {
        SUPPRESS_UNUSED_VARIABLE_WARNING(alloc_size);
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

    //
    // SyntaxObject
    //

    OBJECT SyntaxObject::to_datum(GcThreadFrontEnd* gc_tfe) const {
        return SyntaxObject::data_to_datum(gc_tfe, m_data);
    }
    OBJECT SyntaxObject::data_to_datum(GcThreadFrontEnd* gc_tfe, OBJECT data) {
        if (data.is_pair()) {
            return pair_data_to_datum(gc_tfe, data);
        }
        else if (data.is_vector()) {
            return vector_data_to_datum(gc_tfe, data);
        }
        else {
            assert(data.is_atom());
            return data;
        }
    } 
    OBJECT SyntaxObject::pair_data_to_datum(GcThreadFrontEnd* gc_tfe, OBJECT pair_data) {
        assert(pair_data.is_pair());

        // std::cerr << "pair_data_to_datum: " << pair_data << std::endl;

        auto p = pair_data.as_pair_p();

        // pair-list (possibly improper) of syntax objects
        OBJECT new_car = OBJECT::null;
        OBJECT new_cdr = OBJECT::null;
        if (p->car().is_syntax()) {
            new_car = p->car().as_syntax_p()->to_datum(gc_tfe);
        }
        else if (p->car().is_symbol()) {
            auto sym = p->car().as_symbol();
            
            bool is_pseudo_atom = false; {    
                if (sym == g_id_cache().reference) {
                    is_pseudo_atom = true;
                    // (reference ...) can return as is
                    return pair_data;
                }
                if (sym == g_id_cache().mutation) {
                    is_pseudo_atom = true;
                    // (mutation ...) can return as is
                    return pair_data;
                }
                if (sym == g_id_cache().expanded_lambda) {
                    // (_ ((arg-syntax-object-list ...)) (non-local-vars ...) body-syntax)
                    auto args = extract_args<3>(p->cdr());
                    OBJECT arg_stx_list = args[0];
                    OBJECT non_local_vars = args[1];
                    OBJECT body_stx = args[2];
                    
                    std::cerr << "expanded-lambda: " << p->cdr() << std::endl;
                    
                    return list(gc_tfe,
                        p->car(),
                        (arg_stx_list.is_null() ?
                            arg_stx_list :
                            pair_data_to_datum(gc_tfe, arg_stx_list)),
                        non_local_vars,
                        body_stx
                    );
                }
                if (sym == g_id_cache().expanded_define) {
                    // (_ 'scope 'name-id init)
                    auto args = extract_args<3>(p->cdr());
                    OBJECT rel_var_scope_sym_obj = args[0];
                    OBJECT def_id_obj_stx = args[1];
                    OBJECT body_stx = args[2];

                    assert(rel_var_scope_sym_obj.is_symbol());
                    assert(def_id_obj_stx.is_syntax());
                    assert(body_stx.is_syntax());

                    OBJECT def_id_obj = def_id_obj_stx.as_syntax_p()->data();
                    assert(def_id_obj.is_integer());
                    ssize_t def_id = def_id_obj.as_integer();

                    return list(gc_tfe,
                        p->car(),
                        rel_var_scope_sym_obj,
                        OBJECT::make_integer(def_id),
                        body_stx.as_syntax_p()->to_datum(gc_tfe)
                    );
                }
            }
            if (is_pseudo_atom) {
                new_car = p->car();
            } else {
                goto malformed_syntax_object_error;
            }
        }
        else {
            goto malformed_syntax_object_error;
        }

        if (p->cdr().is_syntax()) {
            // improper list
            new_cdr = p->cdr().as_syntax_p()->to_datum(gc_tfe);
        } else if (p->cdr().is_pair()) {
            // proper list => recurse
            new_cdr = pair_data_to_datum(gc_tfe, p->cdr());
        } else {
            assert(p->cdr().is_atom());
            new_cdr = p->cdr();
        }
        return cons(gc_tfe, new_car, new_cdr);

    malformed_syntax_object_error:
        std::stringstream ss;
        ss << "Malformed syntax object: " << std::endl;
        ss << "Expected (car pair) to be syntax OR pseudo-atom symbol" << std::endl;
        ss << "got:  " << p->car() << std::endl;
        ss << "kind: " << obj_kind_name(obj_kind(p->car())) << std::endl;
        error(ss.str());
        throw SsiError();
    }
    OBJECT SyntaxObject::vector_data_to_datum(GcThreadFrontEnd* gc_tfe, OBJECT vec_data) {
        assert(vec_data.is_vector());
        auto p = vec_data.as_vector_p();

        std::vector<OBJECT> res;
        res.resize(p->size(), OBJECT::null);
        for (ssize_t i = 0; i <p->size(); i++) {
            auto it = (*p)[i];
            assert(it.is_syntax());
            res[i] = it.as_syntax_p()->to_datum(gc_tfe);
        }
        return OBJECT::make_ptr(
            new(gc_tfe->allocate_size_class(VectorObject::sci))
            VectorObject(std::move(res))
        );
    }

    //
    // List
    //

    OBJECT cpp_vector_to_list(GcThreadFrontEnd* gc_tfe, std::vector<OBJECT> const& vec) {
        auto raw_mem = gc_tfe->allocate_bytes(sizeof(PairObject) * vec.size());
        auto mem = reinterpret_cast<PairObject*>(raw_mem);
        OBJECT lst = OBJECT::null;
        for (ssize_t i = vec.size()-1; i >= 0; i--) {
            lst = OBJECT::make_ptr(new(mem+i) PairObject(vec[i], lst));
        }
        return lst;
    }
    OBJECT vector_to_list(GcThreadFrontEnd* gc_tfe, OBJECT vec) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (!vec.is_vector()) {
            std::stringstream ss;
            ss << "vector->list: expected 'vec' as first argument, got: " << vec << std::endl;
            throw SsiError();
        }
#endif        
        return cpp_vector_to_list(
            gc_tfe, 
            vec.as_vector_p()->as_cpp_vec()
        );
    }

    //
    // Vector
    //

    std::vector<OBJECT> list_to_cpp_vector(OBJECT lst) {
        std::vector<OBJECT> res;
        for (OBJECT rem = lst; !rem.is_null(); rem = cdr(rem)) {
            res.push_back(car(rem));
        }
        return res;
    }

}   // namespace ss
