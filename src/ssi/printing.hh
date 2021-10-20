#pragma once

#include <ostream>

class Object;
using C_word = int64_t;

void print_obj(Object* obj, std::ostream& out);
void print_obj2(C_word obj, std::ostream& out);