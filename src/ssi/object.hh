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
#include <functional>
#include <cstddef>
#include <cstdint>

#include "core.hh"
#include "intern.hh"
#include "feedback.hh"

//
// Objects:
//

enum class ObjectKind {
    // native primitives:
    Null,
    Boolean,
    Integer,
    FloatingPt,
    Symbol,
    String,
    Pair,
    Vector,
    Lambda,

    // VMA = VM Accelerator
    // The VM uses some data-structures so frequently that they can be optimized.
    // These are also 'opaque' to the user.
    VMA_CallFrame,
    VMA_Closure,

    // EXT = Extension objects
    EXT_Callable
};

class Object {
    friend ObjectKind obj_kind(Object* obj);

  private:
    ObjectKind m_kind;

  protected:
    explicit Object(ObjectKind kind);
    // ObjectKind is stored in a global std::map<Object*, ObjectKind>
    //  - RTTI is rare, especially with AOT type-checking
    //  - naive alternative: use a virtual 'kind' method or data member: bumps sizeof(AnyObject) from 2*size_t to 3*...
  public:
    [[nodiscard]] ObjectKind kind();
};

class BoolObject: public Object {
  private:
    static BoolObject t_storage;
    static BoolObject f_storage;
  public:
    static BoolObject* t;
    static BoolObject* f;
  private:
    bool m_value;
  private:
    BoolObject()
    :   Object(ObjectKind::Boolean),
        m_value()
    {}
    explicit BoolObject(bool value)
    :   BoolObject()
    {
        m_value = value;
    }
  public:
    [[nodiscard]] inline bool value() const { return m_value; }
};
union NumberObjectMemory {
    my_ssize_t integer;
    my_float_t float_pt;
};
class BaseNumberObject: public Object {
  protected:
    NumberObjectMemory m_as;
  protected:
    explicit BaseNumberObject(my_ssize_t integer)
    :   Object(ObjectKind::Integer),
        m_as{.integer = integer}
    {}
    explicit BaseNumberObject(double float_pt)
    :   Object(ObjectKind::FloatingPt),
        m_as{.float_pt = float_pt}
    {}
  public:
    [[nodiscard]] NumberObjectMemory const* mem() const { return &m_as; }
};
class IntObject: public BaseNumberObject {
  public:
    explicit IntObject(my_ssize_t value)
    :   BaseNumberObject(value)
    {}
  public:
    [[nodiscard]] inline my_ssize_t value() const { return m_as.integer; }
    inline void value(my_ssize_t value) { m_as.integer = value; }
};
class FloatObject: public BaseNumberObject {
  public:
    explicit FloatObject(my_float_t value)
    :   BaseNumberObject(value)
    {}
  public:
    [[nodiscard]] inline my_float_t value() const { return m_as.float_pt; }
    inline void value(my_float_t value) { m_as.float_pt = value; }
};
class SymbolObject: public Object {
  private:
    IntStr m_name;
  public:
    SymbolObject() 
    :   Object(ObjectKind::Symbol),
        m_name()
    {}
    explicit SymbolObject(IntStr name)
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
    :   Object(ObjectKind::String),
        m_count(),
        m_bytes()
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
    Object* m_car;
    Object* m_cdr;
  public:
    PairObject() 
    :   Object(ObjectKind::Pair),
        m_car(),
        m_cdr()
    {}
    explicit PairObject(Object* car, Object* cdr)
    :   PairObject()
    {
        m_car = car;
        m_cdr = cdr;
    }
  public:
    [[nodiscard]] inline Object* car() const { return m_car; }
    [[nodiscard]] inline Object* cdr() const { return m_cdr; }
    inline void set_car(Object* o) { m_car = o; }
    inline void set_cdr(Object* o) { m_cdr = o; }
};
class VectorObject: public Object {
  private:
    size_t         m_count;
    Object** m_array;
  public:
    VectorObject()
    :   Object(ObjectKind::Vector),
        m_count(),
        m_array()
    {}
    VectorObject(size_t count, Object** mv_array)
    :   VectorObject()
    {
        m_count = count;
        m_array = mv_array;
    }
  public:
    [[nodiscard]] inline size_t count() const { return m_count; }
    [[nodiscard]] inline Object** array() const { return m_array; }
};

// todo: replace these properties with a reference to a program on the active VM
class LambdaObject: public Object {
  private:
    Object* m_body;
    Object* m_args_list;
  public:
    LambdaObject()
    :   Object(ObjectKind::Lambda),
        m_body(),
        m_args_list()
    {}
    explicit LambdaObject(Object* body, Object* explicit_arg_names_list)
    : LambdaObject()
    {
        m_body = body;
        m_args_list = explicit_arg_names_list;
    }
};

//
// Builtins for VM:
//  - these are used to accelerate the VM.
//  - todo: move to a different file
//

using VmExpID = size_t;

class VMA_CallFrameObject: public Object {
  private:
    VmExpID m_x;
    PairObject* m_e;
    Object* m_r;
    VMA_CallFrameObject* m_opt_parent;

  public:
    VMA_CallFrameObject(
        VmExpID x,
        PairObject* e,
        Object* r,
        VMA_CallFrameObject* opt_parent
    )
    :   Object(ObjectKind::VMA_CallFrame),
        m_x(x),
        m_e(e),
        m_r(r),
        m_opt_parent(opt_parent)
    {}

  public:
    VmExpID x() const { return m_x; }
    PairObject* e() const { return m_e; }
    Object* r() const { return m_r; }
    VMA_CallFrameObject* parent() const { return m_opt_parent; }
};

class VMA_ClosureObject: public Object {
  private:
    VmExpID m_body;         // the body expression to evaluate
    PairObject* m_e;        // the environment to use
    Object* m_vars;         // the formal variables captured

  public:
    VMA_ClosureObject(
        VmExpID body,
        PairObject* e,
        Object* vars
    )
    :   Object(ObjectKind::VMA_Closure),
        m_body(body),
        m_e(e),
        m_vars(vars)
    {}

  public:
    [[nodiscard]] VmExpID body() const { return m_body; }
    [[nodiscard]] PairObject* e() const { return m_e; }
    [[nodiscard]] Object* vars() const { return m_vars; }
};

//
// EXT_: Extension objects: used to inject C++ code into the runtime
//

using EXT_CallableCb = std::function<Object*(Object* args)>;

class EXT_CallableObject: public Object {
  private:
    EXT_CallableCb m_cb;
    PairObject* m_e;
    Object* m_vars;

  public:
    EXT_CallableObject(EXT_CallableCb cb, PairObject* e, Object* vars)
    :   Object(ObjectKind::EXT_Callable),
        m_cb(std::move(cb)),
        m_e(e),
        m_vars(vars)
    {}

  public:
    EXT_CallableCb const& cb() const { return m_cb; }
    PairObject* e() const { return m_e; }
    Object* vars() const { return m_vars; }
};

//
//
// Inline functions:
//
//

//
// decls
//

inline ObjectKind obj_kind(Object* object);
inline Object* car(Object* object);
inline Object* cdr(Object* object);
template <typename... Objects> Object* list(Objects... objs);
template <size_t n> std::array<Object*, n> extract_args(Object* pair_list, bool is_variadic = false);
inline PairObject* cons(Object* head, Object* tail);
inline Object* boolean(bool v);
inline bool is_boolean(Object* o);
inline bool is_char(Object* o);
inline bool is_null(Object* o);
inline bool is_pair(Object* o);
inline bool is_procedure(Object* o);
inline bool is_symbol(Object* o);
inline bool is_integer(Object* o);
inline bool is_float(Object* o);
inline bool is_string(Object* o);
inline bool is_vector(Object* o);

bool is_eqn(Object* e1, Object* e2);
bool is_eq(Object* e1, Object* e2);
bool is_eqv(Object* e1, Object* e2);
bool is_equal(Object* e1, Object* e2);

inline my_ssize_t count_list_items(Object* pair_list);

//
// defs
//

template <typename... Objects>
Object* list() {
    return nullptr;
}
template <typename... Objects>
Object* list(Object* first, Objects... objs) {
    return new PairObject(first, list(objs...));
}

inline ObjectKind Object::kind() {
    return m_kind;
}
inline ObjectKind obj_kind(Object* object) {
    if (object) {
        return object->kind();
    } else {
        return ObjectKind::Null;
    }
}

template <size_t n> 
std::array<Object*, n> extract_args(Object* pair_list, bool is_variadic) {
    // reading upto `n` objects into an array:
    Object* rem_list = pair_list;
    std::array<Object*, n> out{};
    size_t index = 0;
    while (rem_list && index < n) {
        out[index++] = car(rem_list);
        rem_list = cdr(rem_list);
    }
    
    // checking that the received array is OK:
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    {
        if (!is_variadic && rem_list) {
            std::stringstream error_ss;
            error_ss
                << "extract_args: too many arguments to a non-variadic procedure: expected " << n;
            error(error_ss.str());
            throw SsiError();
        }
        if (index < n) {
            std::stringstream error_ss;
            error_ss 
                << "extract_args: too few arguments: received " << index << ", but expected at least " << n; 
            error(error_ss.str());
            throw SsiError();
        }
    }
#endif

    // returning array:
    return out;
}

inline Object::Object(ObjectKind kind)
:   m_kind(kind) {}

inline Object* car(Object* object) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    if (obj_kind(object) != ObjectKind::Pair) {
        error("car: expected argument object to be a pair");
        throw SsiError();
    }
#endif
    return static_cast<PairObject*>(object)->car();
}
inline Object* cdr(Object* object) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    if (obj_kind(object) != ObjectKind::Pair) {
        error("cdr: expected argument object to be a pair");
        throw SsiError();
    }
#endif
    return static_cast<PairObject*>(object)->cdr();
}

PairObject* cons(Object* head, Object* tail) {
    return new PairObject(head, tail);
}

Object* boolean(bool v) {
    return v ? BoolObject::t : BoolObject::f;
}

inline bool is_boolean(Object* o) {
    return obj_kind(o) == ObjectKind::Boolean;
}
inline bool is_null(Object* o) {
    return obj_kind(o) == ObjectKind::Null;
}
inline bool is_pair(Object* o) {
    return obj_kind(o) == ObjectKind::Pair;
}
inline bool is_procedure(Object* o) {
    return (
        obj_kind(o) == ObjectKind::VMA_Closure ||
        obj_kind(o) == ObjectKind::EXT_Callable
    );
}
inline bool is_symbol(Object* o) {
    return obj_kind(o) == ObjectKind::Symbol;
}
inline bool is_integer(Object* o) {
    return obj_kind(o) == ObjectKind::Integer;
}
inline bool is_float(Object* o) {
    return obj_kind(o) == ObjectKind::FloatingPt;
}
inline bool is_string(Object* o) {
    return obj_kind(o) == ObjectKind::String;
}
inline bool is_vector(Object* o) {
    return obj_kind(o) == ObjectKind::Vector;
}

inline my_ssize_t count_list_items(Object* pair_list) {
    my_ssize_t var_ctr = 0;
    for (
        Object* rem_var_rib = pair_list;
        rem_var_rib;
        rem_var_rib = cdr(rem_var_rib)
    ) {
        var_ctr++;
    }
    return var_ctr;
}