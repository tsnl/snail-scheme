#pragma once

#include <cstddef>
#include <cstdint>

#include "core.hh"
#include "intern.hh"
#include "procedure.hh"

//
// Objects:
//

enum class ObjectKind {
    Nil,
    Boolean,
    Integer,
    FloatingPt,
    Identifier,
    String,
    Pair,
    Vector,
    Procedure
};

class Object {
  public:
    virtual ObjectKind kind() const = 0;
};
class BoolObject: public Object {
  private:
    bool m_value;
  public:
    explicit BoolObject(bool value)
    :   m_value(value)
    {}
  public:
    virtual ObjectKind kind() const override { return ObjectKind::Boolean; }
    inline bool value() const { return m_value; }
};
class IntObject: public Object {
  private:
    my_ssize_t m_value;
  public:
    explicit IntObject(my_ssize_t value)
    :   m_value(value)
    {}
  public:
    virtual ObjectKind kind() const override { return ObjectKind::Integer; }
    inline my_ssize_t value() const { return m_value; }
};
class FloatObject: public Object {
  private:
    double m_value;
  public:
    explicit FloatObject(double value)
    :   m_value(value)
    {}
  public:
    virtual ObjectKind kind() const override { return ObjectKind::FloatingPt; }
    inline double value() const { return m_value; }
};
class IdentifierObject: public Object {
  private:
    IntStr m_name;
  public:
    IdentifierObject(IntStr name)
    :   m_name(name)
    {}
  public:
    virtual ObjectKind kind() const override { return ObjectKind::Identifier; }
    inline IntStr name() const { return m_name; }
};
class StringObject: public Object {
  private:
    size_t m_count;
    char* m_bytes;
  public:
    StringObject(size_t count, char* bytes)
    :   m_count(count),
        m_bytes(bytes)
    {}
  public:
    virtual ObjectKind kind() const override { return ObjectKind::String; }
    inline size_t count() const { return m_count; }
    inline char* bytes() const { return m_bytes; }
};
class PairObject: public Object {
  private:
    Object* m_car;
    Object* m_cdr;
  public:
    explicit PairObject(Object* car, Object* cdr)
    :   m_car(car),
        m_cdr(cdr)
    {}
  public:
    virtual ObjectKind kind() const override { return ObjectKind::Pair; }
    inline Object* car() const { return m_car; }
    inline Object* cdr() const { return m_cdr; }
};
class VectorObject: public Object {
  private:
    size_t   m_count;
    Object** m_array;
  public:
    VectorObject(size_t count, Object** mv_array)
    :   m_count(count),
        m_array(mv_array)
    {}
  public:
    virtual ObjectKind kind() const override { return ObjectKind::Vector; }
    inline size_t count() const { return m_count; }
    inline Object** array() const { return m_array; }
};
// class ProcObject: public Object {
//   private:
//     Object* m_body;
//     Object* m_args_list;
//   public:
//     explicit ProcObject(Object* body, Object* implicit_args_vector, Object* explicit_arg_names_list)
//     :   m_body(body),
// };
template <typename... Objects>
Object* list(Objects... objs);

template <typename... Objects>
Object* list() {
    return nullptr;
}

template <typename... Objects>
Object* list(Object* first, Objects... objs) {
    return new PairObject(first, list(objs...));
}

inline ObjectKind objkind(Object* object) {
    if (object) {
        return object->kind();
    } else {
        return ObjectKind::Nil;
    }
}