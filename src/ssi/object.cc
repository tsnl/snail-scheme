#include "object.hh"

#include <map>

std::map<Object const*, ObjectKind> Object::s_nonnil_object_kind_map{};

Object::Object(ObjectKind kind) {
    s_nonnil_object_kind_map[this] = kind;
}
