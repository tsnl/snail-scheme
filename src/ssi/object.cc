#include "object.hh"

#include <map>

std::map<Object*, ObjectKind> Object::s_non_nil_object_kind_map{};
BoolObject BoolObject::t_storage{true};
BoolObject BoolObject::f_storage{false};
BoolObject* BoolObject::t{&BoolObject::t_storage};
BoolObject* BoolObject::f{&BoolObject::f_storage};

Object::Object(ObjectKind kind) {
    s_non_nil_object_kind_map[this] = kind;
}
