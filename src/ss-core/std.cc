#include "ss-core/std.hh"

#include "ss-core/feedback.hh"

#include <cmath>
#include "ss-core/config.hh"
#include "ss-core/vm.hh"
#include "ss-core/object.hh"
#include "ss-core/pinvoke.hh"
#include "ss-core/printing.hh"

///
// Declarations:
//

namespace ss {

    typedef void(*IntFoldCb)(my_ssize_t& accum, my_ssize_t item);
    typedef void(*Float32FoldCb)(float& accum, float item);
    typedef void(*Float64FoldCb)(double& accum, double item);

    static void bind_standard_kind_predicates(VirtualMachine* vm);
    static void bind_standard_pair_procedures(VirtualMachine* vm);
    static void bind_standard_equality_procedures(VirtualMachine* vm);
    static void bind_standard_list_procedures(VirtualMachine* vm);
    static void bind_standard_vector_procedures(VirtualMachine* vm);
    static void bind_standard_logical_operators(VirtualMachine* vm);
    void bind_standard_arithmetic_procedures(VirtualMachine* vm);

    template <IntFoldCb int_fold_cb, Float32FoldCb float32_fold_cb, Float64FoldCb float64_fold_cb>
    void bind_standard_binary_arithmetic_procedure(VirtualMachine* vm, char const* const name_str);
    inline void int_mul_cb(my_ssize_t& accum, my_ssize_t item);
    inline void int_div_cb(my_ssize_t& accum, my_ssize_t item);
    inline void int_rem_cb(my_ssize_t& accum, my_ssize_t item);
    inline void int_add_cb(my_ssize_t& accum, my_ssize_t item);
    inline void int_sub_cb(my_ssize_t& accum, my_ssize_t item);
    inline void float32_mul_cb(float& accum, float item);
    inline void float32_div_cb(float& accum, float item);
    inline void float32_rem_cb(float& accum, float item);
    inline void float32_add_cb(float& accum, float item);
    inline void float32_sub_cb(float& accum, float item);
    inline void float64_mul_cb(double& accum, double item);
    inline void float64_div_cb(double& accum, double item);
    inline void float64_rem_cb(double& accum, double item);
    inline void float64_add_cb(double& accum, double item);
    inline void float64_sub_cb(double& accum, double item);

}   // namespace ss

///
// Implementation
//

namespace ss {

    void bind_standard_kind_predicates(VirtualMachine* vm) {
        vm_bind_platform_procedure(vm,
            "null?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_null(aa[0]));
            },
            {"obj"}
        );
        vm_bind_platform_procedure(vm,
            "boolean?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_boolean(aa[0]));
            },
            {"obj"}
        );
        vm_bind_platform_procedure(vm,
            "pair?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_pair(aa[0]));
            },
            {"obj"}
        );
        vm_bind_platform_procedure(vm,
            "procedure?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_procedure(aa[0]));
            },
            {"obj"}
        );
        vm_bind_platform_procedure(vm,
            "integer?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_integer(aa[0]));
            },
            {"obj"}
        );
        vm_bind_platform_procedure(vm,
            "real?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_float(aa[0]));
            },
            {"obj"}
        );
        vm_bind_platform_procedure(vm,
            "number?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_number(aa[0]));
            },
            {"obj"}
        );
        vm_bind_platform_procedure(vm,
            "symbol?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_symbol(aa[0]));
            },
            {"obj"}
        );
        vm_bind_platform_procedure(vm,
            "string?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_string(aa[0]));
            },
            {"obj"}
        );
        vm_bind_platform_procedure(vm,
            "vector?",
            [](ArgView const& aa) -> OBJECT {
                return boolean(is_vector(aa[0]));
            },
            {"obj"}
        );
    }

    void bind_standard_pair_procedures(VirtualMachine* vm) {
        vm_bind_platform_procedure(vm,
            "cons", 
            [=](ArgView const& aa) -> OBJECT {
                return cons(vm_gc_tfe(vm), aa[0], aa[1]); 
            }, 
            {"ar", "dr"}
        );
        vm_bind_platform_procedure(vm,
            "car", 
            [](ArgView const& aa) -> OBJECT {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                if (!aa[0].is_pair()) {
                    std::stringstream ss;
                    ss << "car: expected pair argument, received: ";
                    print_obj(aa[0], ss);
                    error(ss.str());
                    throw SsiError();
                }
    #endif
                return car(aa[0]); 
            }, 
            {"pair"}
        );
        vm_bind_platform_procedure(vm,
            "cdr", 
            [](ArgView const& aa) -> OBJECT {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                if (!aa[0].is_pair()) {
                    std::stringstream ss;
                    ss << "cdr: expected pair argument, received: ";
                    print_obj(aa[0], ss);
                    error(ss.str());
                    throw SsiError();
                }
    #endif
                return cdr(aa[0]); 
            }, 
            {"pair"}
        );
    }

    void bind_standard_equality_procedures(VirtualMachine* vm) {
        vm_bind_platform_procedure(vm,
            "=",
            [=](ArgView const& aa) -> OBJECT {
                return boolean(is_eqn(aa[0], aa[1]));
            },
            {"lt-arg", "rt-arg"}
        );
        vm_bind_platform_procedure(vm,
            "eq?",
            [=](ArgView const& aa) -> OBJECT {
                return boolean(is_eq(vm_gc_tfe(vm), aa[0], aa[1]));
            },
            {"lt-arg", "rt-arg"}
        );
        vm_bind_platform_procedure(vm,
            "eqv?",
            [=](ArgView const& aa) -> OBJECT {
                return boolean(is_eqv(vm_gc_tfe(vm), aa[0], aa[1]));
            },
            {"lt-arg", "rt-arg"}
        );
        vm_bind_platform_procedure(vm,
            "equal?",
            [=](ArgView const& aa) -> OBJECT {
                return boolean(is_equal(vm_gc_tfe(vm), aa[0], aa[1]));
            },
            {"lt-arg", "rt-arg"}
        );
    }

    void bind_standard_list_procedures(VirtualMachine* vm) {
        vm_bind_platform_procedure(vm,
            "list",
            [=](ArgView const& aa) -> OBJECT {
                OBJECT res = OBJECT::null;
                for (size_t i = 0; i < aa.size(); i++) {
                    res = cons(vm_gc_tfe(vm), aa[i], res);
                }
                return res;
            },
            {"items..."},
            "constructs a list from a sequence of items",
            true
        );
        vm_bind_platform_procedure(vm,
            "length",
            [=](ArgView const& aa) -> OBJECT {
                return list_length(aa[0]);
            },
            {"lst"},
            "returns the number of elements in a list. May be improper.",
            false
        );
        vm_bind_platform_procedure(vm,
            "set-car!",
            [=](ArgView const& aa) -> OBJECT {
                set_car(aa[0], aa[1]);
                return OBJECT::null;
            },
            {"lst", "v"}
        );
        vm_bind_platform_procedure(vm,
            "set-cdr!",
            [=](ArgView const& aa) -> OBJECT {
                set_cdr(aa[0], aa[1]);
                return OBJECT::null;
            },
            {"lst", "v"}
        );
        vm_bind_platform_procedure(vm,
            "member",
            [=](ArgView const& aa) -> OBJECT {
                return list_member(vm_gc_tfe(vm), aa[0], aa[1]);
            },
            {"x", "list"}
        );
    }

    void bind_standard_vector_procedures(VirtualMachine* vm) {
        vm_bind_platform_procedure(vm,
            "vector",
            [=](ArgView const& aa) -> OBJECT {
                std::vector<OBJECT> items;
                items.reserve(aa.size());
                for (size_t i = 0; i < aa.size(); i++) {
                    items[i] = aa[i];
                }
                return OBJECT::make_ptr(
                    new(vm_gc_tfe(vm)->allocate_size_class(VectorObject::sci))
                    VectorObject(std::move(items))
                );
            },
            {"items..."},
            "constructs a list from a sequence of items",
            true
        );
        vm_bind_platform_procedure(vm,
            "vector-length",
            [=](ArgView const& aa) -> OBJECT {
                if (!aa[0].is_vector()) {
                    std::stringstream ss;
                    ss << "vector-ref: expected first arg to be a vector, not " << aa[0] << std::endl;
                    error(ss.str());
                    throw SsiError();
                }
                auto idx = aa[1].as_signed_fixnum();
                auto size = static_cast<VectorObject*>(aa[0].as_ptr())->size();
                return OBJECT::make_integer(size);
            },
            {"vec"},
            "returns length of this vector"
        );
        vm_bind_platform_procedure(vm,
            "vector-ref",
            [=](ArgView const& aa) -> OBJECT {
                if (!aa[0].is_vector()) {
                    std::stringstream ss;
                    ss << "vector-ref: expected first arg to be a vector, not " << aa[0] << std::endl;
                    error(ss.str());
                    throw SsiError();
                }
                if (!aa[1].is_integer()) {
                    std::stringstream ss;
                    ss << "vector-ref: expected second arg to be int, not " << aa[1] << std::endl;
                    error(ss.str());
                    throw SsiError();
                }
                auto idx = aa[1].as_signed_fixnum();
                return static_cast<VectorObject*>(aa[0].as_ptr())->operator[](idx);
            },
            {"vec, pos"},
            "acquires the element of vec at pos, first slot at index 0"
        );
        vm_bind_platform_procedure(vm,
            "vector-set!",
            [=](ArgView const& aa) -> OBJECT {
                if (!aa[0].is_vector()) {
                    std::stringstream ss;
                    ss << "vector-ref: expected first arg to be a vector, not " << aa[0] << std::endl;
                    error(ss.str());
                    throw SsiError();
                }
                if (!aa[1].is_integer()) {
                    std::stringstream ss;
                    ss << "vector-ref: expected second arg to be int, not " << aa[1] << std::endl;
                    error(ss.str());
                    throw SsiError();
                }
                auto idx = aa[1].as_signed_fixnum();
                return static_cast<VectorObject*>(aa[0].as_ptr())->operator[](idx) = aa[2];
            },
            {"vec, pos", "v"},
            "acquires the element of vec at pos, first slot at index 0"
        );
    }

    void bind_standard_logical_operators(VirtualMachine* vm) {
        vm_bind_platform_procedure(vm,
            "and",
            [](ArgView const& args) -> OBJECT {
                for (size_t i = 0; i < 2; i++) {
                    OBJECT maybe_boolean_obj = args[i];

    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                    if (!maybe_boolean_obj.is_boolean()) {
                        std::stringstream ss;
                        ss << "and: expected boolean, received: ";
                        print_obj(maybe_boolean_obj, ss);
                        error(ss.str());
                        throw SsiError();
                    }
    #endif
                    OBJECT boolean_obj = maybe_boolean_obj;
                    if (boolean_obj.is_boolean(false)) {
                        return OBJECT::make_boolean(false);
                    }
                }
                return OBJECT::make_boolean(true);
            },
            {"lt-arg", "rt-arg"}
        );
        vm_bind_platform_procedure(vm,
            "or",
            [](ArgView const& args) -> OBJECT {
                for (size_t i = 0; i < 2; i++) {
                    OBJECT maybe_boolean_obj = args[i];

    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                    if (!maybe_boolean_obj.is_boolean()) {
                        std::stringstream ss;
                        ss << "or: expected boolean, received: ";
                        print_obj(maybe_boolean_obj, ss);
                        error(ss.str());
                        throw SsiError();
                    }
    #endif
                    OBJECT boolean_obj = maybe_boolean_obj;
                    if (boolean_obj.is_boolean(true)) {
                        return OBJECT::make_boolean(true);
                    }
                }
                return OBJECT::make_boolean(false);
            },
            {"lt-arg", "rt-arg"}
        );
    }

    void bind_standard_arithmetic_procedures(VirtualMachine* vm) {
        bind_standard_binary_arithmetic_procedure<int_mul_cb, float32_mul_cb, float64_mul_cb>(vm, "*");
        bind_standard_binary_arithmetic_procedure<int_div_cb, float32_div_cb, float64_div_cb>(vm, "/");
        bind_standard_binary_arithmetic_procedure<int_rem_cb, float32_rem_cb, float64_rem_cb>(vm, "%");
        bind_standard_binary_arithmetic_procedure<int_add_cb, float32_add_cb, float64_add_cb>(vm, "+");
        bind_standard_binary_arithmetic_procedure<int_sub_cb, float32_sub_cb, float64_sub_cb>(vm, "-");
    }
    template <IntFoldCb int_fold_cb, Float32FoldCb float32_fold_cb, Float64FoldCb float64_fold_cb>
    void bind_standard_binary_arithmetic_procedure(VirtualMachine* vm, char const* const name_str) {
        vm_bind_platform_procedure(vm,
            name_str,
            [=](ArgView const& args) -> OBJECT {
                // first, ensuring we have exactly 2 arguments:
                if (args.size() != 2) {
                    std::stringstream ss;
                    ss << "Expected 2 arguments to binary arithmetic operator " << name_str << ": got 0";
                    error(ss.str());
                    throw SsiError();
                }

                // next, determining the kind of the result:
                //  - this is accomplished by performing a linear scan through the arguments
                //  - though inefficient, this ironically improves throughput, presumably by loading cache lines 
                //    containing each operand before 'load'
                bool float64_operand_present = false;
                bool float32_operand_present = false;
                bool int_operand_present = false;
                for (size_t i = 0; i < 2; i++) {
                    OBJECT operand = args[i];
                    if (operand.is_float64()) {
                        float64_operand_present = true;
                    } else if (operand.is_float32()) {
                        float32_operand_present = true;
                    } else if (operand.is_integer()) {
                        int_operand_present = true;
                    } else {
                        // error:
                        std::stringstream ss;
                        ss << "Invalid argument to arithmetic operator " << name_str << ": ";
                        print_obj(operand, ss);
                        error(ss.str());
                        throw SsiError();
                    }
                }

                // next, computing the result of this operation:
                // NOTE: computation broken into several 'hot paths' for frequent operations.
                if (!float64_operand_present && !float32_operand_present) {
                    // adding two integers:
                    auto& aa = args;
                    my_ssize_t res = aa[0].as_signed_fixnum();
                    int_fold_cb(res, aa[1].as_signed_fixnum());
                    return OBJECT::make_integer(res);
                }
                else if (!int_operand_present && !float64_operand_present) {
                    // adding two float32:
                    auto& aa = args;
                    auto res = aa[0].as_float32();
                    float32_fold_cb(res, aa[1].as_float32());
                    return OBJECT::make_float32(res);
                }
                else {
                    // adding two float64:
                    auto& aa = args;
                    auto res = aa[0].as_float64();
                    float64_fold_cb(res, aa[1].as_float64());
                    return OBJECT::make_float64(vm_gc_tfe(vm), res);
                }
            },
            {"lt-arg", "rt-arg"}
        );
    }
    inline void int_mul_cb(my_ssize_t& accum, my_ssize_t item) { accum *= item; }
    inline void int_div_cb(my_ssize_t& accum, my_ssize_t item) { accum /= item; }
    inline void int_rem_cb(my_ssize_t& accum, my_ssize_t item) { accum %= item; }
    inline void int_add_cb(my_ssize_t& accum, my_ssize_t item) { accum += item; }
    inline void int_sub_cb(my_ssize_t& accum, my_ssize_t item) { accum -= item; }
    inline void float32_mul_cb(float& accum, float item) { accum *= item; }
    inline void float32_div_cb(float& accum, float item) { accum /= item; }
    inline void float32_rem_cb(float& accum, float item) { accum = fmod(accum, item); }
    inline void float32_add_cb(float& accum, float item) { accum += item; }
    inline void float32_sub_cb(float& accum, float item) { accum -= item; }
    inline void float64_mul_cb(double& accum, double item) { accum *= item; }
    inline void float64_div_cb(double& accum, double item) { accum /= item; }
    inline void float64_rem_cb(double& accum, double item) { accum = fmod(accum, item); }
    inline void float64_add_cb(double& accum, double item) { accum += item; }
    inline void float64_sub_cb(double& accum, double item) { accum -= item; }

    void bind_standard_console_io_procedures(VirtualMachine* vm) {
        vm_bind_platform_procedure(vm,
            "display",
            [=](ArgView const& aa) -> OBJECT {
                std::cout << aa[0];
                return OBJECT::null;
            },
            {"it"}
        );
        vm_bind_platform_procedure(vm,
            "displayln",
            [=](ArgView const& aa) -> OBJECT {
                std::cout << aa[0] << std::endl;
                return OBJECT::null;
            },
            {"it"}
        );
    }

}   // namespace ss

///
// Interface
//

namespace ss {

    void bind_standard_procedures(VirtualMachine* vm) {
        // error("NotImplemented: bind_standard_procedures");
        // throw SsiError();
        bind_standard_kind_predicates(vm);
        bind_standard_pair_procedures(vm);
        bind_standard_equality_procedures(vm);
        bind_standard_logical_operators(vm);
        bind_standard_list_procedures(vm);
        bind_standard_vector_procedures(vm);
        bind_standard_arithmetic_procedures(vm);
        bind_standard_console_io_procedures(vm);
    }

}