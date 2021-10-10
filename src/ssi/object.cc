#include "object.hh"

#include <map>

std::map<Object const*, ObjectKind> Object::s_non_nil_object_kind_map{};
BoolObject const BoolObject::t_storage{true};
BoolObject const BoolObject::f_storage{false};
BoolObject const* BoolObject::t{&BoolObject::t_storage};
BoolObject const* BoolObject::f{&BoolObject::f_storage};

Object::Object(ObjectKind kind) {
    s_non_nil_object_kind_map[this] = kind;
}

VMA_CallFrameObject::VMA_CallFrameObject(
    Object const* e,
    Object const* r,
    VmExpID x,
    VMA_CallFrameObject* parent
)
:   Object(ObjectKind::VMA_CallFrameObject),
    m_e(e),
    m_r(r),
    m_x(x),
    m_parent(parent)
{}
