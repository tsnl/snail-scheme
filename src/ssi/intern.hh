#pragma once

#include <cstddef>

using IntStr = size_t;

IntStr intern(char const* s);
char const* interned_string(IntStr int_str);
