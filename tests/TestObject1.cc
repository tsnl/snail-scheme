#include <gtest/gtest.h>

#include "ss-core/object.1.hh"
#include <bitset>

///
/// TAG TESTS
/// - may fail due to platform endianness mismatch
///

#define BITS(it) std::bitset<64>((it.as_raw()))
#define DBG_PRINT(it) std::cerr << "             " << it << std::endl

TEST(ObjectTests1, NullTagTests) {
    // Expect Null to be a pointer
    auto iv = 0;
    ss::OBJECT null = ss::OBJECT::null;
    DBG_PRINT("NullTagTests: BITSET: " << BITS(null));
    
    EXPECT_EQ(null.is_null(), 1);
    EXPECT_EQ(null.is_integer(), 0);
    EXPECT_EQ(null.is_boolean(), 0);
    EXPECT_EQ(null.is_float32(), 0);
    EXPECT_EQ(null.is_uchar(), 0);
    EXPECT_EQ(null.is_eof(), 0);
    EXPECT_EQ(null.is_undef(), 0);
    EXPECT_EQ(null.is_interned_symbol(), 0);
    EXPECT_EQ(null.is_boxed_object(), 0);
}
TEST(ObjectTests1, IntTagTests) {
    // Expect signed integer fixnums to have a unique type.
    auto iv = 0;
    ss::OBJECT i1 = ss::OBJECT::make_integer(iv);
    DBG_PRINT("IntTagTests: BITSET: " << BITS(i1));
    EXPECT_EQ(i1.raw_data().signed_fixnum.tag, ss::OBJECT::FIXNUM_TAG);
    EXPECT_EQ(i1.raw_data().signed_fixnum.val, iv);
    
    EXPECT_EQ(i1.is_integer(), 1);
    EXPECT_EQ(i1.is_boolean(), 0);
    EXPECT_EQ(i1.is_float32(), 0);
    EXPECT_EQ(i1.is_uchar(), 0);
    EXPECT_EQ(i1.is_null(), 0);
    EXPECT_EQ(i1.is_eof(), 0);
    EXPECT_EQ(i1.is_undef(), 0);
    EXPECT_EQ(i1.is_interned_symbol(), 0);
    EXPECT_EQ(i1.is_boxed_object(), 0);
}
TEST(ObjectTests1, PtrTagTests) {
    char msg_buf[] = "hello world";
    auto fake_ptr = new ss::StringObject(sizeof(msg_buf), msg_buf);
    // auto fake_ptr = reinterpret_cast<BoxedObject*>(-7);
    ss::OBJECT p1 = ss::OBJECT::make_generic_boxed(fake_ptr);
    ASSERT_EQ(p1.raw_data().ptr_unwrapped.tag, 0) << "invalid fake ptr";
    
    DBG_PRINT("PtrTagTests: FAKPTR: " << std::bitset<64>(reinterpret_cast<size_t>(fake_ptr)));
    DBG_PRINT("PtrTagTests: BITSET: " << std::bitset<64>(p1.as_raw()));
}