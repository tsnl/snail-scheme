#pragma once

#include "object.0.hh"

namespace ss {

    inline GranularObjectType BaseBoxedObject::kind() {
        return m_kind;
    }
    inline GranularObjectType obj_kind(OBJECT object) {
        return object.kind();
    }

    GranularObjectType OBJECT::kind() const {
        if (is_ptr()) { return m_data.ptr->kind(); }
        if (is_integer()) { return GranularObjectType::Fixnum; }
        if (is_interned_symbol()) { return GranularObjectType::InternedSymbol; }
        if (is_float32()) { return GranularObjectType::Float32; }
        if (is_uchar()) { return GranularObjectType::Rune; }
        if (is_boolean()) { return GranularObjectType::Boolean; }
        if (is_null()) { return GranularObjectType::Null; }
        if (is_eof()) { return GranularObjectType::Eof; }
        error("NotImplemented: kind: Unknown OBJECT kind");
        throw SsiError();
    }

    // inline OBJECT OBJECT::make_port(std::string file_path, std::ios_base::openmode mode) {
    //     OBJECT res{new Port};
    // }
    inline OBJECT OBJECT::make_ptr(BaseBoxedObject* obj) {
        return OBJECT{obj};
    }
    inline bool OBJECT::is_pair() const { 
        return is_ptr() && as_ptr()->kind() == GranularObjectType::Pair; 
    }
    inline bool OBJECT::is_float64() const {
        return is_ptr() && as_ptr()->kind() == GranularObjectType::Float64;
    }
    inline bool OBJECT::is_closure() const {
        return is_ptr() && as_ptr()->kind() == GranularObjectType::Vector;
    }
    inline bool OBJECT::is_string() const { 
        return is_ptr() && as_ptr()->kind() == GranularObjectType::String;
    }
    inline bool OBJECT::is_vector() const {
        return is_ptr() && as_ptr()->kind() == GranularObjectType::Vector;
    }
    inline bool OBJECT::is_syntax() const {
        return is_ptr() && as_ptr()->kind() == GranularObjectType::Syntax;
    }
    inline bool OBJECT::is_box() const {
        return is_ptr() && as_ptr()->kind() == GranularObjectType::Box;
    }

    size_t OBJECT::as_raw() const { 
        return m_data.raw; 
    }
    my_ssize_t OBJECT::as_signed_fixnum() const {
        assert(is_integer() && "expected fixnum object");
        return m_data.signed_fixnum.val;
    }
    bool OBJECT::as_boolean() const {
        assert(is_boolean() && "expected boolean object");
        return m_data.raw == s_boolean_t.as_raw();
    }
    BaseBoxedObject* OBJECT::as_ptr() const {
        assert(is_ptr() && "expected boxed object");
        return m_data.ptr;
    }
    IntStr OBJECT::as_interned_symbol() const {
        assert(is_interned_symbol() && "expected interned symbol object");
        return m_data.interned_symbol.val;
    }
    float OBJECT::as_float32() const {
        assert(is_float32() && "expected float32 object");
        return m_data.f32.val;
    }
    double OBJECT::as_float64() const {
        assert(is_float64() && "expected float64 object");
        return static_cast<Float64Object*>(as_ptr())->value();
    }

    inline double OBJECT::to_double() const {
        OBJECT const& it = *this;
        if (it.is_integer()) {
            return static_cast<double>(it.as_signed_fixnum());
        } else if (it.is_float32()) {
            return static_cast<double>(it.as_float32());
        } else if (it.is_float64()) {
            return it.as_float64();
        } else {
            error("Expected number, but got something else.");
            throw SsiError();
        }
    };

    inline void VectorObject::reserve(size_t min_new_capacity) {
        m_impl.reserve(min_new_capacity);
    }
    inline void VectorObject::push(OBJECT object) {
        m_impl.push_back(object);
    }
    template <typename... TArgs>
    void VectorObject::push_many(TArgs... args) {
        size_t count = sizeof...(args);
        m_impl.reserve(m_impl.size() + count);
        push_many_without_reserve(args...);
    }
    template <typename... TArgs>
    void VectorObject::push_many_without_reserve(OBJECT arg, TArgs... args) {
        m_impl.push_back(arg);
        push_many_without_reserve(args...);
    }
    inline void VectorObject::push_many_without_reserve() {}

}