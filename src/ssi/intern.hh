#pragma once

#include <cstddef>
#include <string>

using IntStr = size_t;

IntStr intern(std::string s);
std::string const& interned_string(IntStr int_str);
