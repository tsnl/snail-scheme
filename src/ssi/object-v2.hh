// object-v2 is an improved object system.
// Since pointers must be aligned on 4 bytes on 32-bit systems
// and 8 bytes on 64-bit systems, we have at least 2 bits to use
// for tagging.
// Integers, booleans, and special singletons are stored in a word.
// Only other types dispatch to boxes via pointers.
// NOTE: most of this is based on Chicken Scheme, with modifications for interp:
//  - 64-bit only (for simplicity)
//  - interned symbols are immediates
// TODO: improve object types by eliding boxing for value types:
//  cf https://www.more-magic.net/posts/internals-data-representation.html
//  cf https://github.com/alaricsp/chicken-scheme/blob/1eb14684c26b7c2250ca9b944c6b671cb62cafbc/chicken.h
// TODO: implement a GC, with required support for pointer tagging in place
//  cf https://www.more-magic.net/posts/internals-gc.html

#pragma once

#include <bit>
#include <sstream>
#include <vector>
#include <cstdint>

#include "config/config.hh"
#include "feedback.hh"
#include "heap.hh"
#include "intern.hh"
#include "printing.hh"

//
// Platform checks + utilities
//

using C_word = int64_t;
using C_uword = uint64_t;
static_assert(CONFIG_SIZEOF_VOID_P == 8, "object-v2 only works on 64-bit systems.");
static_assert(sizeof(C_word) == sizeof(double), "object-v2 expected 64-bit double.");
static_assert(sizeof(C_word) == sizeof(void*), "expected word size to be pointer size.");

#define C_wordstobytes(n)          ((n) << 3)
#define C_bytestowords(n)          (((n) + 7) >> 3)

//
// Immediate data-types:
//

// lifted straight out of `chicken.h`, except
//  - convention of 'WRAP_' and 'UNWRAP_' to convert datatypes to C_word
//  * C_fix -> C_WRAP_INT
//  * C_unfix -> C_UNWRAP_INT
//  * C_make_character -> C_WRAP_CHAR
//  * C_character_code -> C_UNWRAP_CHAR
//  * MOST_{POSITIVE|NEGATIVE}_FIXNUM -> MOST_$1_INT

#define C_IMMEDIATE_MARK_BITS       0x3                 // '0b11' bits: at least 1 true for all immediate values
#define C_BOOLEAN_BIT_MASK          0x0000000f          // '0b1111' because all info in last nibble
#define C_BOOLEAN_BITS              0x00000006          // '0b0110' suffix
#define C_CHAR_BITS                 0x0000000a          // '0b1010' suffix
#define C_SYMBOL_BITS               0x00000042          // '0b00101010' suffix
#define C_SYMBOL_VALUE_CHK_BITS     0x00ffffffffffffff  // all but the most significant byte is OK
#define C_CHAR_VALUE_CHK_BITS       0x1fffff            // restricts to representable UTF-8 range
#define C_CHAR_SHIFT                8                   // waste a full 8 bits; use 56 to store code point
#define C_SYMBOL_SHIFT              8                   // waste a full 8 bits; use 56 to store symbol ID.
#define C_SPECIAL_BITS              0x0000000e          // '0b1110'
#define C_SCHEME_FALSE              ((C_word)(C_BOOLEAN_BITS | 0x00))
#define C_SCHEME_TRUE               ((C_word)(C_BOOLEAN_BITS | 0x10))
#define C_INT_BIT                   0x00000001      // '0b1'-- most important type
#define C_INT_SHIFT                 1               // just 1 bit wasted

// WRAP_INT and UNWRAP_INT encode a integer value as a word and decode a word as an int resp.
#define C_WRAP_INT(n)               (((C_word)(n) << C_INT_SHIFT) | C_INT_BIT)
#define C_UNWRAP_INT(x)             ((x) >> C_INT_SHIFT)
// WRAP_CHAR and UNWRAP_CHAR encode a char value as a word and decode a word as a char resp.
#define C_WRAP_CHAR(c)              ((((c) & C_CHAR_VALUE_CHK_BITS) << C_CHAR_SHIFT) | C_CHAR_BITS)
#define C_UNWRAP_CHAR(x)            (((x) >> C_CHAR_SHIFT) & C_CHAR_VALUE_CHK_BITS)
// WRAP_SYMBOL and UNWRAP_SYMBOL are the same as above
#define C_WRAP_SYMBOL(s)            (((s) << C_SYMBOL_SHIFT) | C_SYMBOL_BITS)
#define C_UNWRAP_SYMBOL(s)          (((s) >> C_SYMBOL_SHIFT) & C_SYMBOL_VALUE_CHK_BITS)

// special values:
#define C_SCHEME_END_OF_LIST        ((C_word)(C_SPECIAL_BITS | 0x00000000))
#define C_SCHEME_UNDEFINED          ((C_word)(C_SPECIAL_BITS | 0x00000010))
// #define C_SCHEME_UNBOUND         ((C_word)(C_SPECIAL_BITS | 0x00000020))
#define C_SCHEME_END_OF_FILE        ((C_word)(C_SPECIAL_BITS | 0x00000030))

// determining limits:
#define C_MOST_POSITIVE_INT         (0x3fffffffffffffffL)
#define C_WORD_SIZE_IN_BITS         (64)
#define C_MOST_NEGATIVE_INT         (-C_MOST_POSITIVE_INT - 1)
#define C_MAX_CHAR                  (0x00ffffff)

//
// Block data-types:
//

using C_header = C_uword;

struct C_SCHEME_BLOCK {
    C_header header;    // header: bit pattern (see below)
    C_word data[0];     // variable length array
};
static_assert(sizeof(C_SCHEME_BLOCK) == sizeof(C_word));

// bit flags to mask integers:
#define C_INT_SIGN_BIT           0x8000000000000000L
#define C_INT_TOP_BIT            0x4000000000000000L
// header bit masks: most significant byte gives type+GC, rem bytes give size
//  less sig nibble gives type
//  more sig nibble gives GC flags
#define C_HEADER_BITS_MASK       0xff00000000000000L
#define C_HEADER_TYPE_BITS       0x0f00000000000000L
#define C_HEADER_SIZE_MASK       0x00ffffffffffffffL
#define C_GC_FORWARDING_BIT      0x8000000000000000L   /* header contains forwarding pointer */
#define C_BYTEBLOCK_BIT          0x4000000000000000L   /* block contains bytes instead of slots */
#define C_SPECIALBLOCK_BIT       0x2000000000000000L   /* 1st item is a non-value */
#define C_8ALIGN_BIT             0x1000000000000000L   /* data is aligned to 8-byte boundary */
// type nibbles:
#define C_STRING_HEADER_BITS            (0x0200000000000000L | C_BYTEBLOCK_BIT)
#define C_PAIR_HEADER_BITS              (0x0300000000000000L)
#define C_CLOSURE_HEADER_BITS           (0x0400000000000000L | C_SPECIALBLOCK_BIT)
#define C_FLONUM_HEADER_BITS            (0x0500000000000000L | C_BYTEBLOCK_BIT | C_8ALIGN_BIT)
// #define C_PORT_HEADER_BITS           (0x0700000000000000L | C_SPECIALBLOCK_BIT)
// #define C_STRUCTURE_TYPE             (0x0800000000000000L)
// #define C_POINTER_TYPE               (0x0900000000000000L | C_SPECIALBLOCK_BIT)
// #define C_LOCATIVE_TYPE              (0x0a00000000000000L | C_SPECIALBLOCK_BIT)
// #define C_TAGGED_POINTER_TYPE        (0x0b00000000000000L | C_SPECIALBLOCK_BIT)
// #define C_SWIG_POINTER_TYPE          (0x0c00000000000000L | C_SPECIALBLOCK_BIT)
// #define C_LAMBDA_INFO_TYPE           (0x0d00000000000000L | C_BYTEBLOCK_BIT)
//       unused                         (0x0e00000000000000L ...)
// #define C_BUCKET_TYPE                (0x0f00000000000000L)
#define C_VECTOR_HEADER_BITS            (0x0000000000000000L)
#define C_BYTE_VECTOR_HEADER_BITS       (C_VECTOR_HEADER_BITS | C_BYTEBLOCK_BIT | C_8ALIGN_BIT)

// Size calculation macros: measured in 'words', i.e. 8-bytes
#define C_SIZEOF_PAIR                   (3)
#define C_SIZEOF_LIST(n)                (C_SIZEOF_PAIR * (n) + 1)
#define C_SIZEOF_STRING(n)              (C_bytestowords(n) + 2)     /* 1 extra byte for null-terminator; works with C */
#define C_SIZEOF_FLONUM                 (2)
// #define C_SIZEOF_PORT                (16)
#define C_SIZEOF_VECTOR(n)              ((n) + 1)

// Fixed size types have pre-computed header tags (1-byte):
// NOTE: the 'size' bits measure size in bytes.
#define C_PAIR_TAG                      (C_PAIR_HEADER_BITS | (C_SIZEOF_PAIR - 1))
// #define C_POINTER_TAG                (C_POINTER_TYPE | (C_SIZEOF_POINTER - 1))
// #define C_LOCATIVE_TAG               (C_LOCATIVE_TYPE | (C_SIZEOF_LOCATIVE - 1))
// #define C_TAGGED_POINTER_TAG         (C_TAGGED_POINTER_TYPE | (C_SIZEOF_TAGGED_POINTER - 1))
// #define C_SWIG_POINTER_TAG           (C_SWIG_POINTER_TYPE | (C_wordstobytes(C_SIZEOF_SWIG_POINTER - 1)))
#define C_FLONUM_TAG                    (C_FLONUM_HEADER_BITS | sizeof(double))

//
// Interface functions:
//

// testing just 1 bit:
inline bool is_integer(C_word word) {
    return word & C_INT_BIT;
}
// testing least-significant nibble:
inline bool is_bool(C_word word) { return (word & 0x0f) == C_BOOLEAN_BITS; }
// testing least-significant byte:
inline bool is_char(C_word word) { return (word & 0xff) == C_CHAR_BITS; }
inline bool is_symbol(C_word word) { return (word & 0xff) == C_SYMBOL_BITS; }
inline bool is_undefined(C_word word) { return word == C_SCHEME_UNDEFINED; }
inline bool is_eol(C_word word) { return word == C_SCHEME_END_OF_LIST; }
inline bool is_eof(C_word word) { return word == C_SCHEME_END_OF_FILE; }
inline bool is_block_ptr(C_word word) {
    return (word & C_IMMEDIATE_MARK_BITS) == 0;
}
inline bool is_immediate(C_word word) {
    return !is_block_ptr(word);
}
inline int64_t block_size(C_word word) {
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(word);
    return static_cast<int64_t>(bp->header & C_HEADER_SIZE_MASK);
}
inline bool is_string(C_word word) {
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(word);
    return is_block_ptr(word) && ((bp->header & C_HEADER_BITS_MASK) == C_STRING_HEADER_BITS);
}
inline bool is_pair(C_word word) {
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(word);
    return is_block_ptr(word) && (bp->header == C_PAIR_TAG);
}
inline bool is_flonum(C_word word) {
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(word);
    return is_block_ptr(word) && (bp->header == C_FLONUM_TAG);
}
inline bool is_vector(C_word word) {
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(word);
    return is_block_ptr(word) && ((bp->header & C_HEADER_BITS_MASK) == C_VECTOR_HEADER_BITS);
}
inline bool is_byte_vector(C_word word) {
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(word);
    return is_block_ptr(word) && ((bp->header & C_HEADER_BITS_MASK) == C_BYTE_VECTOR_HEADER_BITS);
}
inline bool is_closure(C_word word) {
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(word);
    return is_block_ptr(word) && ((bp->header & C_HEADER_BITS_MASK) == C_CLOSURE_HEADER_BITS);
}
inline int64_t string_length(C_word word) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    if (!is_string(word)) {
        std::stringstream ss;
        ss << "string-length: expected argument to be string, got: ";
        print_obj2(word, ss);
        // print_obj(word, ss);
        error(ss.str());
        throw SsiError();
    }
#endif
    // NOTE: for string, we store size in bytes (since byte-block)
    return block_size(word);
}
inline int string_ref(C_word word, int64_t i) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    if (!is_string(word)) {
        std::stringstream ss;
        ss << "string-ref: expected 1st argument to be string, got: ";
        print_obj2(word, ss);
        error(ss.str());
        throw SsiError();
    }
#endif
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(word);
    return static_cast<int>(reinterpret_cast<uint8_t*>(bp->data)[i]);
}
inline int64_t vector_length(C_word word) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    if (!is_vector(word)) {
        std::stringstream ss;
        ss << "vector-length: expected argument to be vector, got: ";
        print_obj2(word, ss);
        error(ss.str());
        throw SsiError();
    }
#endif
    // NOTE: for vector, we store size in words.
    return block_size(word) - 1;
}
inline C_word vector_ref(C_word vec, int64_t index) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    if (!is_vector(vec)) {
        std::stringstream ss;
        ss << "vector-ref: expected 1st argument to be vector, got: <todo-- print object>";
        // print_obj(word, ss);
        error(ss.str());
        throw SsiError();
    }
#endif
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(vec);
    return bp->data[index];
}
inline void vector_set(C_word vec, int64_t index, C_word new_val) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    if (!is_vector(vec)) {
        std::stringstream ss;
        ss << "vector-ref: expected 1st argument to be vector, got: <todo-- print object>";
        // print_obj(word, ss);
        error(ss.str());
        throw SsiError();
    }
#endif
    auto bp = reinterpret_cast<C_SCHEME_BLOCK*>(vec);
    bp->data[index] = new_val;
}

//
// Constructors:
//

inline C_word c_symbol(IntStr int_str_id);
inline C_word c_boolean(bool bit);
inline C_word c_integer(int64_t value);
inline C_word c_char(int value);
inline C_word c_cons(C_word ar, C_word dr);
inline C_word c_vector(std::vector<C_word> objs);
template <typename... TObjs> C_word c_list(TObjs... ar_objs);

inline C_word c_symbol(IntStr int_str_id) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    if (int_str_id & ~C_SYMBOL_VALUE_CHK_BITS) {
        std::stringstream ss;
        ss << "c_symbol: absolute value of symbol (IntStr ID) too large: " << int_str_id;
        error(ss.str());
        throw SsiError();
    }
#endif
    return (int_str_id << C_SYMBOL_SHIFT) | C_SYMBOL_BITS;
}
inline C_word c_boolean(bool bit) {
    if (bit) {
        return C_SCHEME_TRUE;
    } else {
        return C_SCHEME_FALSE;
    }
}
inline C_word c_integer(int64_t value) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    if (value > C_MOST_POSITIVE_INT) {
        std::stringstream ss;
        ss << "c_integer: absolute value of integer too large: " << value;
        error(ss.str());
        throw SsiError();
    }
    if (value < C_MOST_NEGATIVE_INT) {
        std::stringstream ss;
        ss << "c_integer: absolute value of integer too small: " << value;
        error(ss.str());
        throw SsiError();
    }
#endif
    return C_WRAP_INT(value);
}
inline C_word c_char(int value) {
    return C_WRAP_CHAR(value);
}
inline C_word c_flonum(double v) {
    auto mp = static_cast<C_SCHEME_BLOCK*>(heap_allocate(C_wordstobytes(C_SIZEOF_FLONUM)));
    mp->header = C_FLONUM_TAG;
    memcpy(mp->data, &v, sizeof(C_word));
    return reinterpret_cast<C_word>(mp);
}
inline C_word c_cons(C_word ar, C_word dr) {
    auto mp = static_cast<C_SCHEME_BLOCK*>(heap_allocate(C_wordstobytes(C_SIZEOF_PAIR)));
    mp->header = C_PAIR_TAG;
    mp->data[0] = ar;
    mp->data[1] = dr;
    return reinterpret_cast<C_word>(mp);
}
inline C_word c_vector(std::vector<C_word> objs) {
    auto mp = static_cast<C_SCHEME_BLOCK*>(heap_allocate(C_wordstobytes(C_SIZEOF_VECTOR(objs.size()))));
    mp->header = C_VECTOR_HEADER_BITS | 1+objs.size();
    memcpy(mp->data, objs.data(), C_wordstobytes(objs.size()));
    return reinterpret_cast<C_word>(mp);
}
inline C_word c_string(std::string const& utf8_data) {
    auto mp = static_cast<C_SCHEME_BLOCK*>(heap_allocate(C_SIZEOF_STRING(utf8_data.size())));
    mp->header = C_STRING_HEADER_BITS | utf8_data.size();
    memcpy(mp->data, utf8_data.c_str(), 1+utf8_data.size());
    return reinterpret_cast<C_word>(mp);
}

template <typename... TObjs> C_word c_list_helper(C_SCHEME_BLOCK* mem, TObjs... rem);
template <typename... TObjs> C_word c_list_helper(C_SCHEME_BLOCK* mem) {
    // do not write to memory
    return C_SCHEME_END_OF_LIST;
}
template <typename... TObjs> C_word c_list_helper(C_SCHEME_BLOCK* mem, C_word ar_obj, TObjs... rem) {
    mem->header = C_PAIR_TAG;
    mem->data[0] = ar_obj;
    mem->data[1] = c_list_helper(
        reinterpret_cast<C_SCHEME_BLOCK*>(reinterpret_cast<C_word*>(mem) + C_SIZEOF_PAIR),
        rem...
    );
    return reinterpret_cast<C_word>(mem);
}
template <typename... TObjs> C_word c_list(TObjs... ar_objs) {
    size_t n = sizeof...(TObjs);
    auto mem = static_cast<C_SCHEME_BLOCK*>(heap_allocate(C_wordstobytes(C_SIZEOF_LIST(n))));
    return c_list_helper(mem, ar_objs...);
}

//
// Utility functions in scheme:
//

inline C_word c_is_integer(C_word word) { return c_boolean(is_integer(word)); }
inline C_word c_is_bool(C_word word) { return c_boolean(is_bool(word)); }
inline C_word c_is_char(C_word word) { return c_boolean(is_char(word)); }
inline C_word c_is_undefined(C_word word) { return c_boolean(is_undefined(word)); }
inline C_word c_is_eol(C_word word) { return c_boolean(is_eol(word)); }
inline C_word c_is_eof(C_word word) { return c_boolean(is_eof(word)); }
inline C_word c_is_string(C_word word) { return c_boolean(is_string(word)); }
inline C_word c_is_pair(C_word word) { return c_boolean(is_pair(word)); }
inline C_word c_is_flonum(C_word word) { return c_boolean(is_flonum(word)); }
inline C_word c_is_vector(C_word word) { return c_boolean(is_vector(word)); }
inline C_word c_is_byte_vector(C_word word) { return c_boolean(is_byte_vector(word)); }
inline C_word c_is_closure(C_word word) { return c_boolean(is_closure(word)); }
