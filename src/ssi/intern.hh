#pragma once

#include <cstddef>
#include <string>

#include "config/config.hh"

using IntStr = int64_t;
static_assert(CONFIG_SIZEOF_VOID_P == 8, "intstr: expected 64-bit machine");

IntStr intern(std::string s);
std::string const& interned_string(IntStr int_str);
