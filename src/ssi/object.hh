// `Object` is the shared monotype for this Scheme.
//  - it is generated by a parser
//  - the 'vm' module...
//      1.  compiles objects into 'ch3 assembly code' objects
//      2.  executes ch3 assembly code objects using other objects
//      ?.  performs GC on a relevant subset of all allocated nodes.
//          - this leaks code objects, which is great, because we need them to be loaded permanently
//          - can dispose of code objects post-execution in the future

#pragma once

#include <map>
#include <array>
#include <sstream>
#include <cstddef>
#include <cstdint>

#include "core.hh"
#include "intern.hh"
#include "procedure.hh"
#include "feedback.hh"

//
// Objects:
//

enum class ObjectKind {
    Nil,
    Boolean,
    Integer,
    FloatingPt,
    Symbol,
    String,
    Pair,
    Vector,
    Procedure
};

class Object {
  public:
    static std::map<Object const*, ObjectKind> s_nonnil_object_kind_map;
  protected:
    Object(ObjectKind kind);
    // ObjectKind is stored in a global std::map<Object*, ObjectKind>
    //  - RTTI is rare, especially with AOT type-checking
    //  - naive alternative: use a virtual 'kind' method or data member: bumps sizeof(AnyObject) from 2*size_t to 3*...
  public:
    ObjectKind kind() const;
};

class BoolObject: public Object {
  private:
    bool m_value;
  public:
    BoolObject()
    :   Object(ObjectKind::Boolean)
    {}
    explicit BoolObject(bool value)
    :   BoolObject()
    {
        m_value = value;
    }
  public:
    inline bool value() const { return m_value; }
};
class IntObject: public Object {
  private:
    my_ssize_t m_value;
  public:
    IntObject()
    :   Object(ObjectKind::Integer)
    {}
    explicit IntObject(my_ssize_t value)
    :   IntObject()
    {
        m_value = value;
    }
  public:
    inline my_ssize_t value() const { return m_value; }
};
class FloatObject: public Object {
  private:
    double m_value;
  public:
    FloatObject() 
    :   Object(ObjectKind::FloatingPt)
    {}
    explicit FloatObject(double value)
    :   FloatObject()
    {
        m_value = value;
    }
  public:
    inline double value() const { return m_value; }
};
class SymbolObject: public Object {
  private:
    IntStr m_name;
  public:
    SymbolObject() 
    :   Object(ObjectKind::Symbol)
    {}
    SymbolObject(IntStr name)
    :   SymbolObject()
    {
        m_name = name;
    }
  public:
    inline IntStr name() const { return m_name; }
};
class StringObject: public Object {
  private:
    size_t m_count;
    char* m_bytes;
  public:
    StringObject()
    :   Object(ObjectKind::String)
    {}
    StringObject(size_t count, char* bytes)
    :   StringObject()
    {
        m_count = count;
        m_bytes = bytes;
    }
  public:
    inline size_t count() const { return m_count; }
    inline char* bytes() const { return m_bytes; }
};
class PairObject: public Object {
  private:
    Object const* m_car;
    Object const* m_cdr;
  public:
    PairObject() 
    :   Object(ObjectKind::Pair)
    {}
    explicit PairObject(Object const* car, Object const* cdr)
    :   PairObject()
    {
        m_car = car;
        m_cdr = cdr;
    }
  public:
    inline Object const* car() const { return m_car; }
    inline Object const* cdr() const { return m_cdr; }
};
class VectorObject: public Object {
  private:
    size_t         m_count;
    Object const** m_array;
  public:
    VectorObject()
    :   Object(ObjectKind::Vector)
    {}
    VectorObject(size_t count, Object const** mv_array)
    :   VectorObject()
    {
        m_count = count;
        m_array = mv_array;
    }
  public:
    inline size_t count() const { return m_count; }
    inline Object const** array() const { return m_array; }
};
class ProcObject: public Object {
  private:
    Object const* m_body;
    Object const* m_args_list;
  public:
    ProcObject()
    :   Object(ObjectKind::Procedure)
    {}
    explicit ProcObject(Object const* body, Object const* explicit_arg_names_list)
    :   ProcObject()
    {
        m_body = body;
        m_args_list = explicit_arg_names_list;
    }
};

//
//
// Inline functions:
//
//

//
// decls
//

inline ObjectKind objkind(Object const* object);
inline Object const* car(Object const* object);
inline Object const* cdr(Object const* object);
template <typename... Objects> Object const* list(Objects... objs);
template <size_t n> std::array<Object const*, n> extract_args(Object const* pair_list, bool is_variadic = false);

//
// defs
//

template <typename... Objects>
Object const* list() {
    return nullptr;
}
template <typename... Objects>
Object const* list(Object const* first, Objects... objs) {
    return new PairObject(first, list(objs...));
}

inline ObjectKind Object::kind() const {
    return Object::s_nonnil_object_kind_map[this];
}
inline ObjectKind objkind(Object const* object) {
    if (object) {
        return object->kind();
    } else {
        return ObjectKind::Nil;
    }
}

template <size_t n> 
std::array<Object const*, n> extract_args(Object const* pair_list, bool is_variadic) {
    // reading upto `n` objects into an array:
    Object const* rem_list = pair_list;
    std::array<Object const*, n> out{};
    size_t index = 0;
    while (rem_list) {
        out[index++] = car(rem_list);
        rem_list = cdr(rem_list);
    }
    
    // checking that the received array is OK:
#if !CONFIG_OPTIMIZED_MODE
    {
        if (!is_variadic && rem_list) {
            error("extract_args: too many arguments to a non-variadic procedure");
            throw SsiError();
        }
        if (index < n) {
            std::stringstream error_ss;
            error_ss 
                << "extract_args: too few arguments: received " << 1+index << ", but expected at least " << n; 
            error(error_ss.str());
            throw SsiError();
        }
    }
#endif

    // returning array:
    return out;
}

inline Object const* car(Object const* object) {
#if !CONFIG_OPTIMIZED_MODE
    if (objkind(object) != ObjectKind::Pair) {
        error("car: expected argument object to be a pair");
        throw SsiError();
    }
#endif
    return static_cast<PairObject const*>(object)->car();
}
inline Object const* cdr(Object const* object) {
#if !CONFIG_OPTIMIZED_MODE
    if (objkind(object) != ObjectKind::Pair) {
        error("cdr: expected argument object to be a pair");
        throw SsiError();
    }
#endif
    return static_cast<PairObject const*>(object)->cdr();
}
