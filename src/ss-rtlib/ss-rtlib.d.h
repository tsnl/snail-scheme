// NOTE: prefix convention
// - 'Ssrt_' => provided by RTLib
// - 'SsrtReq_' => provided by implementation, linked by 'extern' and resolved by linking at IR-level

#pragma once

#include <stdint.h>
#include <stdbool.h>

///
// Only works on 64-bit systems
//

static_assert(sizeof(void*) == 8);

///
// CharSpan for string literals, symbols
//

typedef struct Ssrt_Bytes Ssrt_Bytes;
struct Ssrt_Bytes {
    char* data;
    uint64_t count;
};

///
// Interned strings
//

typedef uint64_t Ssrt_IntStr;

Ssrt_IntStr intern();
Ssrt_Bytes interned_string(Ssrt_IntStr sc);

///
// Object
//

typedef uint64_t Ssrt_OBJECT;

Ssrt_OBJECT Ssrt_OBJECT_wrap_integer(size_t v);
Ssrt_OBJECT Ssrt_OBJECT_wrap_float32(float v);
Ssrt_OBJECT Ssrt_OBJECT_wrap_symbol(Ssrt_IntStr sc);
Ssrt_OBJECT Ssrt_OBJECT_wrap_boolean(bool v);
Ssrt_OBJECT Ssrt_OBJECT_wrap_null();
Ssrt_OBJECT Ssrt_OBJECT_wrap_undef();
Ssrt_OBJECT Ssrt_OBJECT_wrap_eof();

size_t Ssrt_OBJECT_unwrap_integer(Ssrt_OBJECT o);
float Ssrt_OBJECT_unwrap_float32(Ssrt_OBJECT o);
Ssrt_IntStr Ssrt_OBJECT_unwrap_symbol(Ssrt_OBJECT o);
bool Ssrt_OBJECT_unwrap_boolean(bool v);

bool Ssrt_OBJECT_is_boolean(Ssrt_OBJECT o);
bool Ssrt_OBJECT_is_null(Ssrt_OBJECT o);
bool Ssrt_OBJECT_is_undef(Ssrt_OBJECT o);
bool Ssrt_OBJECT_is_eof(Ssrt_OBJECT o);
bool Ssrt_OBJECT_is_integer(Ssrt_OBJECT o);
bool Ssrt_OBJECT_is_float32(Ssrt_OBJECT o);
bool Ssrt_OBJECT_is_symbol(Ssrt_OBJECT o);

// todo: add more bindings

///
// GC
//