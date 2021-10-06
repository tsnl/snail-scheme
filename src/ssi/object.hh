#pragma once

#include <cstddef>
#include <cstdint>

#include "core.hh"
#include "intern.hh"
#include "procedure.hh"

enum class ObjectKind {
    Bool,
    Int,
    Float,
    Identifier,
    String,
    Pair,
    Vector,
    Procedure
};

class Object {
  public:
    ObjectKind kind() const;
};
class BoolObject: public Object {
  private:
    bool m_value;
  public:
    explicit BoolObject(bool value);
};
class IntObject: public Object {
  private:
    my_ssize_t m_value;
  public:
    explicit IntObject(bool value);
};
class FloatObject: public Object {
  private:
    double m_value;
  public:
    explicit FloatObject(double value);
};
class IdentifierObject: public Object {
  private:
    IntStr m_name;
  public:
    IdentifierObject(IntStr name);
};
class StringObject: public Object {
  private:
    size_t m_count;
    char* m_bytes;
  public:
    StringObject(size_t count, char* bytes);
};
class PairObject: public Object {
  private:
    Object* m_car;
    Object* m_cdr;
  public:
    explicit PairObject(Object* car, Object* cdr);
};
class VectorObject: public Object {
  private:
    size_t   m_count;
    Object** m_array;
  public:
    VectorObject(size_t count, Object** mv_array);
};
class ProcObject: public Object {
  private:
    Object* body;
    Object* args_list;
  public:
    explicit ProcObject(Object* body, Object* implicit_args_vector, Object* explicit_arg_names_list);
};
