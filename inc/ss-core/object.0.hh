// `Object` is the shared monotype for this Scheme.
//  - it is generated by a parser
//  - the 'vm' module...
//      1.  compiles objects into 'ch3 assembly code' objects
//      2.  executes ch3 assembly code objects using other objects
//      ?.  performs GC on a relevant subset of all allocated nodes.
//          - this leaks code objects, which is great, because we need them to be loaded permanently
//          - can dispose of code objects post-execution in the future

#pragma once

#include <map>
#include <array>
#include <sstream>
#include <functional>
#include <bitset>
#include <ostream>
#include <cstddef>
#include <cstdint>
#include <vector>
#include <ios>
#include <cassert>
#include <cstdint>

#include "ss-core/common.hh"
#include "ss-core/file-loc.hh"
#include "ss-core/intern.hh"
#include "ss-core/feedback.hh"
#include "ss-core/gc.d.hh"

namespace ss {

    //
    // Objects:
    //

    enum class ObjectKind: int8_t {
        Null, Eof,
        Box,
        Boolean,
        Fixnum,
        Float32,
        Float64,
        Rune,
        InternedSymbol,
        String,
        Pair,
        Vector,
        Syntax
    };

    class BaseBoxedObject;
    class PairObject;
    class VectorObject;
    class SyntaxObject;
    class ArrayObject;

    class OBJECT {
        // NOTE: 'nullptr' <=> 'null' for interop with C++
    public:
        inline static size_t const PTR_TAG = 0b0;
        inline static size_t const FIXNUM_TAG = 0b1;
        inline static size_t const INTSTR_TAG = 0b10;
        inline static size_t const HALFWORD_TAG = 0b100;
        inline static size_t const FL32_TAG  = (0b000 << 3) | HALFWORD_TAG;
        inline static size_t const RUNE_TAG  = (0b001 << 3) | HALFWORD_TAG;
        inline static size_t const BOOL_TAG  = (0b010 << 3) | HALFWORD_TAG;
        inline static size_t const EOF_TAG   = (0b011 << 3) | HALFWORD_TAG;
        inline static size_t const UNDEF_TAG = (0b100 << 3) | HALFWORD_TAG;

    private:
        union Data64LittleEndian {
            size_t raw: 64;
            
            // must be a multiple of '8', so ends in '000'
            // actually always a ptr to 'BaseBoxedObject'
            BaseBoxedObject* ptr;
            struct { size_t tag: 3; size_t word_offset: 61; } ptr_unwrapped;
            
            // signed fixnum: ends in '1 << 0 = 0b1'
            struct { size_t tag: 1; int64_t val: 63; } signed_fixnum;
            // interned symbol: ends in '1 << 1 = 0b10'
            struct { size_t tag: 2; int64_t val: 62; } interned_symbol;
            
            // half-words: ends in '1 << 2 = 0b100' aka HALFWORD_TAG
            // next 3MSB in tag are used for finer division
            struct { uint32_t tag: 6; uint32_t pad: 26; float val; } f32;
            struct { uint64_t tag: 6; uint64_t rune: 58; } rune;
            struct { uint64_t tag: 6; uint64_t truth: 58; } boolean;
            struct { uint64_t tag: 6; uint64_t pad: 58; } eof;
            struct { uint64_t tag: 6; uint64_t pad: 58; } undef;
        };
        Data64LittleEndian m_data;
    // unboxed representation:
    private:
        static const OBJECT s_boolean_t;
        static const OBJECT s_boolean_f;
    public:
        static const OBJECT null;
        static const OBJECT undef;
        static const OBJECT eof;
    public:
        constexpr OBJECT() = default;
        constexpr OBJECT(OBJECT const& other) = default;
        constexpr OBJECT(OBJECT&& other) = default; 
        explicit constexpr OBJECT(bool v) 
        :   OBJECT() 
        {
            m_data.boolean.tag = BOOL_TAG;
            m_data.boolean.truth = v;
        }
        explicit constexpr OBJECT(BaseBoxedObject* ptr)
        :   OBJECT()
        {
            m_data.ptr = ptr;
            assert(m_data.ptr_unwrapped.tag == 0 && "Expected ptr to be a multiple of sizeof(void*)");
        }
        explicit constexpr OBJECT(IntStr v) 
        :   OBJECT()
        {
            m_data.interned_symbol.val = v;
            m_data.interned_symbol.tag = INTSTR_TAG;
        }
    public:
        inline constexpr static OBJECT make_integer(ssize_t val) {
            OBJECT res;
            res.m_data.signed_fixnum.tag = FIXNUM_TAG;
            res.m_data.signed_fixnum.val = val;
            return res;
        }
        inline constexpr static OBJECT make_symbol(IntStr s) {
            OBJECT res;
            res.m_data.interned_symbol.tag = INTSTR_TAG;
            res.m_data.interned_symbol.val = s;
            return res;
        }
        inline constexpr static OBJECT make_float32(float f32) {
            OBJECT res;
            res.m_data.f32.tag = FL32_TAG;
            res.m_data.f32.val = f32;
            return res;
        }
        inline constexpr static OBJECT make_boolean(bool v) {
            return v ? s_boolean_t : s_boolean_f;
        }
    private:
        inline constexpr static OBJECT make_undef() {
            OBJECT res;
            res.m_data.undef.tag = UNDEF_TAG;
            return res;
        }
        inline constexpr static OBJECT make_null() {
            return OBJECT{nullptr};
        }
        inline constexpr static OBJECT make_eof() {
            OBJECT res;
            res.m_data.eof.tag = EOF_TAG;
            return res;
        }
    public: // boxed objects
        // static OBJECT make_port(std::string file_path, std::ios_base::openmode mode);
        static OBJECT make_ptr(BaseBoxedObject* obj);
        static OBJECT make_float64(GcThreadFrontEnd* gc_tfe, double f64);
        static OBJECT make_box(GcThreadFrontEnd* gc_tfe, OBJECT stored);
        static OBJECT make_pair(GcThreadFrontEnd* gc_tfe, OBJECT head, OBJECT tail);
        static OBJECT make_string(GcThreadFrontEnd* gc_tfe, size_t byte_count, char* mv_bytes, bool collect_bytes);
        static OBJECT make_vector(GcThreadFrontEnd* gc_tfe, std::vector<OBJECT> raw);
        static OBJECT make_syntax(GcThreadFrontEnd* gc_tfe, OBJECT data, FLoc loc);
    public:
        bool is_null() const { return m_data.raw == 0; }
        bool is_ptr() const { return m_data.ptr_unwrapped.tag == PTR_TAG && !is_null(); }
        bool is_integer() const { return m_data.signed_fixnum.tag == FIXNUM_TAG; }
        bool is_symbol() const { return m_data.interned_symbol.tag == INTSTR_TAG; }
        bool is_float32() const { return m_data.f32.tag == FL32_TAG; }
        bool is_uchar() const { return m_data.rune.tag == RUNE_TAG; }
        bool is_boolean() const { return m_data.boolean.tag == BOOL_TAG; }
        bool is_boolean(bool v) const { return is_boolean() && as_raw() == (v ? s_boolean_t.as_raw() : s_boolean_f.as_raw()); }
        bool is_eof() const { return m_data.eof.tag == EOF_TAG; }
        bool is_undef() const { return m_data.undef.tag == UNDEF_TAG; }
        bool is_list() const { return is_pair() || is_null(); }
    public:
        inline bool is_pair() const;
        inline bool is_float64() const;
        inline bool is_closure() const;
        inline bool is_string() const;
        inline bool is_vector() const;
        inline bool is_syntax() const;
        inline bool is_box() const;     // beware: different than 'IsBoxedObject'
    public:
        inline ObjectKind kind() const;
    public:
        inline bool is_atom() const;
    public:
        inline size_t as_raw() const;
        inline ssize_t as_integer() const;
        inline bool as_boolean() const;
        inline BaseBoxedObject* as_ptr() const;
        inline IntStr as_symbol() const;
        inline float as_float32() const;
        inline double as_float64() const;
    public:
        inline double to_double() const;
    public:
        inline PairObject* as_pair_p() const;
        inline VectorObject* as_vector_p() const;
        inline SyntaxObject* as_syntax_p() const;
    public:
        Data64LittleEndian raw_data() const { return m_data; }
    public:
        OBJECT& operator=(OBJECT const& other) = default;
    };

    class BaseBoxedObject {
        friend ObjectKind obj_kind(OBJECT obj);

    private:
        gc::SizeClassIndex m_sci;
        uint8_t m_gc_tfid;
        ObjectKind m_kind;
        
    protected:
        explicit BaseBoxedObject(ObjectKind kind);
        virtual ~BaseBoxedObject() = default;

    public:
        void* operator new(size_t allocation_size, void* placement_ptr);
        void* operator new(size_t allocation_size, GcThreadFrontEnd* gc_tfe, gc::SizeClassIndex sci);
        void operator delete(void* ptr, GcThreadFrontEnd* gc_tfe, gc::SizeClassIndex sci);
        void operator delete(void* ptr, size_t size_in_bytes);
        void operator delete(void* ptr);
    private:
        void delete_();

    public:
        [[nodiscard]] ObjectKind kind();
    };
    static_assert(sizeof(OBJECT) == 8);
    static_assert(sizeof(OBJECT) == sizeof(void*));

    class BoxObject: public BaseBoxedObject {
    private:
        OBJECT m_boxed;
    
    public:
        inline explicit BoxObject(OBJECT boxed)
        :   BaseBoxedObject(ObjectKind::Box),
            m_boxed(std::move(boxed))
        {}

    public:
        OBJECT& boxed() { return m_boxed; }
    };

    class Float64Object: public BaseBoxedObject {
    protected:
        double m_value;
    public:
        explicit Float64Object(double float_pt)
        :   BaseBoxedObject(ObjectKind::Float64),
            m_value(float_pt)
        {}
    public:
        double value() const { return m_value; }
    };

    class StringObject: public BaseBoxedObject {
    private:
        size_t m_count;
        char* m_bytes;
        bool m_bytes_gc_collectable;
    public:
        StringObject()
        :   BaseBoxedObject(ObjectKind::String),
            m_count(),
            m_bytes()
        {}
        StringObject(size_t count, char* bytes, bool collect_bytes)
        :   StringObject()
        {
            m_count = count;
            m_bytes = bytes;
            m_bytes_gc_collectable = collect_bytes;
        }
    public:
        inline size_t count() const { return m_count; }
        inline char* bytes() const { return m_bytes; }
    };

    class PairObject: public BaseBoxedObject {
    private:
        OBJECT m_car;
        OBJECT m_cdr;
    public:
        explicit PairObject(OBJECT car, OBJECT cdr)
        :   BaseBoxedObject(ObjectKind::Pair),
            m_car(car),
            m_cdr(cdr)
        {}
        PairObject() 
        :   PairObject(OBJECT::null, OBJECT::null)
        {}
    public:
        [[nodiscard]] inline OBJECT car() const { return m_car; }
        [[nodiscard]] inline OBJECT cdr() const { return m_cdr; }
        inline void set_car(OBJECT o) { m_car = o; }
        inline void set_cdr(OBJECT o) { m_cdr = o; }
    };

    class VectorObject: public BaseBoxedObject {
    public:
        static const gc::SizeClassIndex sci;

    private:
        std::vector<OBJECT> m_impl;

    public:
        VectorObject()
        :   BaseBoxedObject(ObjectKind::Vector),
            m_impl()
        {}
        VectorObject(std::vector<OBJECT>&& items)
        :   BaseBoxedObject(ObjectKind::Vector),
            m_impl(std::move(items))
        {}

    private:
        void push_many_without_reserve();
        
        template <typename... TArgs>
        void push_many_without_reserve(OBJECT object, TArgs... args);

    public:
        void reserve(size_t min_new_capacity);

        void push(OBJECT object);
        
        template <typename... TArgs>
        void push_many(TArgs... args);

    public:
        OBJECT& operator[] (size_t i) {
            return m_impl[i];
        }
        ssize_t size() {
            return m_impl.size();
        }

    public:
        [[nodiscard]] inline size_t count() const { return m_impl.size(); }
        [[nodiscard]] inline OBJECT* array() { return m_impl.data(); }
        inline std::vector<OBJECT>& as_cpp_vec() { return m_impl; }
    };

    class SyntaxObject: public BaseBoxedObject {
    public:
        static const gc::SizeClassIndex sci;
    
    private:
        OBJECT m_data;
        FLoc m_loc;
        
    public:
        inline SyntaxObject(OBJECT data, FLoc loc)
        :   BaseBoxedObject(ObjectKind::Syntax),
            m_data(data),
            m_loc(loc)
        {}
    
    public:
        [[nodiscard]] inline OBJECT data() const { return m_data; }
        [[nodiscard]] inline FLoc loc() const { return m_loc; }

    public:
        OBJECT to_datum(GcThreadFrontEnd* gc_tfe) const;
    
    private:
        static OBJECT data_to_datum(GcThreadFrontEnd* gc_tfe, OBJECT data);
        static OBJECT pair_data_to_datum(GcThreadFrontEnd* gc_tfe, OBJECT pair_data);
        static OBJECT vector_data_to_datum(GcThreadFrontEnd* gc_tfe, OBJECT vec_data);
    };

    //
    //
    // Inline functions:
    //
    //

    //
    // decls
    //

    std::ostream& operator<<(std::ostream& out, const OBJECT& obj);

    inline ObjectKind obj_kind(OBJECT object);
    inline std::string obj_kind_name(ObjectKind object_kind);
    inline OBJECT car(OBJECT object);
    inline OBJECT cdr(OBJECT object);
    inline OBJECT cadr(OBJECT object) { return car(cdr(object)); }
    inline OBJECT cddr(OBJECT object) { return cdr(cdr(object)); }
    inline OBJECT caddr(OBJECT object) { return car(cdr(cdr(object))); }
    inline OBJECT cdddr(OBJECT object) { return cdr(cdr(cdr(object))); }
    inline OBJECT cadddr(OBJECT object) { return car(cdr(cdr(cdr(object)))); }
    inline OBJECT cddddr(OBJECT object) { return cdr(cdr(cdr(cdr(object)))); }
    inline void set_car(OBJECT pair, OBJECT a);
    inline void set_cdr(OBJECT pair, OBJECT d);
    inline void set_box(OBJECT box, OBJECT new_stored);
    template <typename... Objects> OBJECT list(GcThreadFrontEnd* gc_tfe, Objects... objs);
    template <size_t n> std::array<OBJECT, n> extract_args(OBJECT pair_list, bool is_variadic = false);
    inline OBJECT box(GcThreadFrontEnd* gc_tfe, OBJECT boxed);
    inline OBJECT cons(GcThreadFrontEnd* gc_tfe, OBJECT head, OBJECT tail);
    inline OBJECT boolean(bool v);
    inline bool is_boolean(OBJECT o);
    inline bool is_char(OBJECT o);
    inline bool is_null(OBJECT o);
    inline bool is_box(OBJECT o);
    inline bool is_pair(OBJECT o);
    inline bool is_procedure(OBJECT o);
    inline bool is_symbol(OBJECT o);
    inline bool is_integer(OBJECT o);
    inline bool is_float(OBJECT o);
    inline bool is_number(OBJECT o);
    inline bool is_string(OBJECT o);
    inline bool is_vector(OBJECT o);
    
    bool is_eqn(OBJECT e1, OBJECT e2);
    bool is_eq(OBJECT e1, OBJECT e2);
    bool is_eqv(GcThreadFrontEnd* gc_tfe, OBJECT e1, OBJECT e2);
    bool is_equal(GcThreadFrontEnd* gc_tfe, OBJECT e1, OBJECT e2);

    inline ssize_t list_length(OBJECT pair_list);
    inline OBJECT list_member(OBJECT x, OBJECT lst);
    OBJECT cpp_vector_to_list(GcThreadFrontEnd* gc_tfe, std::vector<OBJECT> const& vec);
    OBJECT vector_to_list(GcThreadFrontEnd* gc_tfe, OBJECT vec);
    
    inline OBJECT vector_length(OBJECT vec);
    inline OBJECT vector_ref(OBJECT vec, OBJECT index);
    inline void vector_set(OBJECT vec, OBJECT index, OBJECT v);
    std::vector<OBJECT> list_to_cpp_vector(OBJECT lst);

    //
    // defs
    //

    template <typename... Objects>
    OBJECT list(GcThreadFrontEnd* gc_tfe) {
        (void)gc_tfe;       // no-op marking usable
        return OBJECT::null;
    }
    template <typename... Objects>
    OBJECT list(GcThreadFrontEnd* gc_tfe, OBJECT first, Objects... objs) {
        return OBJECT::make_pair(gc_tfe, first, list(gc_tfe, objs...));
    }

    template <size_t n> 
    std::array<OBJECT, n> extract_args(OBJECT pair_list, bool is_variadic) {
        if (!pair_list.is_list()) {
            std::stringstream ss;
            ss  << "extract_args: invalid args: " << pair_list << std::endl;
            error(ss.str());
            throw SsiError();
        }
        
        // reading upto `n` objects into an array:
        OBJECT rem_list = pair_list;
        std::array<OBJECT, n> out;
        size_t index = 0;
        while (!rem_list.is_null() && index < n) {
            if (!rem_list.is_pair()) {
                std::stringstream ss;
                ss  << "invalid item in list: " << rem_list << std::endl
                    << "list: " << pair_list << std::endl;
                error(ss.str());
                throw SsiError();
            };
            out[index++] = car(rem_list);
            rem_list = cdr(rem_list);
        }
        
        // checking that the received array is OK:
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        {
            if (!is_variadic && !rem_list.is_null()) {
                std::stringstream error_ss;
                error_ss
                    << "extract_args: too many arguments to a non-variadic procedure: expected " << n;
                error(error_ss.str());
                throw SsiError();
            }
            if (index < n) {
                std::stringstream error_ss;
                error_ss 
                    << "extract_args: too few arguments: received " << index << ", but expected at least " << n; 
                error(error_ss.str());
                throw SsiError();
            }
        }
    #endif

        // returning array:
        return out;
    }

    inline BaseBoxedObject::BaseBoxedObject(ObjectKind kind)
    :   m_kind(kind) {}

    inline OBJECT car(OBJECT object) {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (!object.is_pair()) {
            error("car: expected argument object to be a pair");
            throw SsiError();
        }
    #endif
        return object.as_pair_p()->car();
    }
    inline OBJECT cdr(OBJECT object) {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (obj_kind(object) != ObjectKind::Pair) {
            error("cdr: expected argument object to be a pair");
            throw SsiError();
        }
    #endif
        return object.as_pair_p()->cdr();
    }
    inline void set_car(OBJECT pair, OBJECT a) {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (!is_pair(pair)) {
            error("set-car!: expected argument object to be a pair");
            throw SsiError();
        }
    #endif
        return pair.as_pair_p()->set_car(a);
    }
    inline void set_cdr(OBJECT pair, OBJECT d) {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (!is_pair(pair)) {
            error("set-cdr!: expected argument object to be a pair");
            throw SsiError();
        }
    #endif
        return pair.as_pair_p()->set_cdr(d);
    }

    inline OBJECT unbox(OBJECT box) {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (!is_box(box)) {
            std::stringstream ss;
            ss << "unbox: expected argument object to be a box, instead got " << box;
            error(ss.str());
            throw SsiError();
        }
    #endif
        return static_cast<BoxObject*>(box.as_ptr())->boxed();
    }
    inline void set_box(OBJECT box, OBJECT new_stored) {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (!is_box(box)) {
            std::stringstream ss;
            ss << "unbox: expected argument object to be a box, instead got " << box;
            error(ss.str());
            throw SsiError();
        }
    #endif
        static_cast<BoxObject*>(box.as_ptr())->boxed() = new_stored;
    }

    inline OBJECT box(GcThreadFrontEnd* gc_tfe, OBJECT stored) {
        return OBJECT::make_box(gc_tfe, stored);
    }

    inline OBJECT cons(GcThreadFrontEnd* gc_tfe, OBJECT head, OBJECT tail) {
        return OBJECT::make_pair(gc_tfe, head, tail);
    }

    inline OBJECT boolean(bool v) {
        return OBJECT::make_boolean(v);
    }

    inline bool is_boolean(OBJECT o) {
        return o.is_boolean();
    }
    inline bool is_null(OBJECT o) {
        return o.is_null();
    }
    inline bool is_box(OBJECT o) {
        return o.is_box();
    }
    inline bool is_pair(OBJECT o) {
        return obj_kind(o) == ObjectKind::Pair;
    }
    inline bool is_procedure(OBJECT o) {
        return o.is_closure();
    }
    inline bool is_symbol(OBJECT o) {
        return o.is_symbol();
    }
    inline bool is_integer(OBJECT o) {
        return o.is_integer();
    }
    inline bool is_float(OBJECT o) {
        return o.is_float64() || o.is_float32();
    }
    inline bool is_number(OBJECT o) {
        return is_integer(o) || is_float(o);
    }
    inline bool is_string(OBJECT o) {
        return o.is_string();
    }
    inline bool is_vector(OBJECT o) {
        return o.is_vector();
    }

    inline ssize_t list_length(OBJECT pair_list) {
        ssize_t var_ctr = 0;
        for (
            OBJECT rem_var_rib = pair_list;
            rem_var_rib.is_pair();
            rem_var_rib = cdr(rem_var_rib)
        ) {
            var_ctr++;
        }
        return var_ctr;
    }
    inline OBJECT list_member(OBJECT x, OBJECT lst) {
        for (OBJECT rem = lst; rem.is_pair(); rem = cdr(rem)) {
            if (is_eq(car(rem), x)) {
                return rem;
            }
        }
        return OBJECT::make_boolean(false);
    }
    
    inline OBJECT vector_length(OBJECT vec) {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (!vec.is_vector()) {
            std::stringstream ss;
            ss << "vector-length: expected 'vec' as first argument, got: " << vec << std::endl;
            error(ss.str());
            throw SsiError();
        }
    #endif
        return OBJECT::make_integer(dynamic_cast<VectorObject*>(vec.as_ptr())->count());
    }
    inline OBJECT vector_ref(OBJECT vec, OBJECT index) {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (!vec.is_vector()) {
            std::stringstream ss;
            ss << "vector-ref: expected 'vec' as first argument, got: " << vec << std::endl;
            error(ss.str());
            throw SsiError();
        }
        if (!index.is_integer()) {
            std::stringstream ss;
            ss << "vector-ref: expected 'int' as second argument, got: " << vec << std::endl;
            error(ss.str());
            throw SsiError();
        }
    #endif
        return dynamic_cast<VectorObject*>(vec.as_ptr())->operator[](index.as_integer());
    }
    inline void vector_set(OBJECT vec, OBJECT index, OBJECT v) {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
        if (!vec.is_vector()) {
            std::stringstream ss;
            ss << "vector-set!: expected 'vec' as first argument, got: " << vec << std::endl;
            error(ss.str());
            throw SsiError();
        }
        if (!index.is_integer()) {
            std::stringstream ss;
            ss << "vector-set!: expected 'int' as second argument, got: " << vec << std::endl;
            error(ss.str());
            throw SsiError();
        }
    #endif
        dynamic_cast<VectorObject*>(vec.as_ptr())->operator[](index.as_integer()) = v;
    }

}   // namespace ss
