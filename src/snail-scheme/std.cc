#include "snail-scheme/std.hh"

#include <cmath>
#include "ss-config/config.hh"
#include "snail-scheme/vm.hh"
#include "snail-scheme/object.hh"
#include "snail-scheme/printing.hh"

///
// Declarations:
//

typedef void(*IntFoldCb)(my_ssize_t& accum, my_ssize_t item);
typedef void(*Float32FoldCb)(float& accum, float item);
typedef void(*Float64FoldCb)(double& accum, double item);

static void bind_standard_kind_predicates(VirtualMachine* vm);
static void bind_standard_pair_procedures(VirtualMachine* vm);
static void bind_standard_equality_procedures(VirtualMachine* vm);
static void bind_standard_list_procedures(VirtualMachine* vm);
static void bind_standard_logical_operators(VirtualMachine* vm);
void bind_standard_arithmetic_procedures(VirtualMachine* vm);

template <IntFoldCb int_fold_cb, Float32FoldCb float32_fold_cb, Float64FoldCb float64_fold_cb>
void bind_standard_variadic_arithmetic_procedure(VirtualMachine* vm, char const* const name_str);
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

///
// Implementation
//

void bind_standard_kind_predicates(VirtualMachine* vm) {
    define_builtin_procedure_in_vm(vm,
        "null?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_null(aa[0]));
        },
        {"obj"}
    );
    define_builtin_procedure_in_vm(vm,
        "boolean?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_boolean(aa[0]));
        },
        {"obj"}
    );
    define_builtin_procedure_in_vm(vm,
        "pair?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_pair(aa[0]));
        },
        {"obj"}
    );
    define_builtin_procedure_in_vm(vm,
        "procedure?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_procedure(aa[0]));
        },
        {"obj"}
    );
    define_builtin_procedure_in_vm(vm,
        "integer?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_integer(aa[0]));
        },
        {"obj"}
    );
    define_builtin_procedure_in_vm(vm,
        "real?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_float(aa[0]));
        },
        {"obj"}
    );
    define_builtin_procedure_in_vm(vm,
        "number?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_number(aa[0]));
        },
        {"obj"}
    );
    define_builtin_procedure_in_vm(vm,
        "symbol?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_symbol(aa[0]));
        },
        {"obj"}
    );
    define_builtin_procedure_in_vm(vm,
        "string?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_string(aa[0]));
        },
        {"obj"}
    );
    define_builtin_procedure_in_vm(vm,
        "vector?",
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
            return boolean(is_vector(aa[0]));
        },
        {"obj"}
    );
}

void bind_standard_pair_procedures(VirtualMachine* vm) {
    define_builtin_procedure_in_vm(vm,
        "cons", 
        [vm](OBJECT args) -> OBJECT {
            auto aa = extract_args<2>(args);
            return cons(vm_gc_tfe(vm), aa[0], aa[1]); 
        }, 
        {"ar", "dr"}
    );
    define_builtin_procedure_in_vm(vm,
        "car", 
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
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
    define_builtin_procedure_in_vm(vm,
        "cdr", 
        [](OBJECT args) -> OBJECT {
            auto aa = extract_args<1>(args);
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
    define_builtin_procedure_in_vm(vm,
        "=",
        [vm](OBJECT args) -> OBJECT {
            auto aa = extract_args<2>(args);
            return boolean(is_eqn(aa[0], aa[1]));
        },
        {"lt-arg", "rt-arg"}
    );
    define_builtin_procedure_in_vm(vm,
        "eq?",
        [vm](OBJECT args) -> OBJECT {
            auto aa = extract_args<2>(args);
            return boolean(is_eq(vm_gc_tfe(vm), aa[0], aa[1]));
        },
        {"lt-arg", "rt-arg"}
    );
    define_builtin_procedure_in_vm(vm,
        "eqv?",
        [vm](OBJECT args) -> OBJECT {
            auto aa = extract_args<2>(args);
            return boolean(is_eqv(vm_gc_tfe(vm), aa[0], aa[1]));
        },
        {"lt-arg", "rt-arg"}
    );
    define_builtin_procedure_in_vm(vm,
        "equal?",
        [vm](OBJECT args) -> OBJECT {
            auto aa = extract_args<2>(args);
            return boolean(is_equal(vm_gc_tfe(vm), aa[0], aa[1]));
        },
        {"lt-arg", "rt-arg"}
    );
}

void bind_standard_list_procedures(VirtualMachine* vm) {
    define_builtin_procedure_in_vm(vm,
        "list",
        [](OBJECT args) -> OBJECT {
            return args;
        },
        {"items..."}
    );
}

void bind_standard_logical_operators(VirtualMachine* vm) {
    define_builtin_procedure_in_vm(vm,
        "and",
        [](OBJECT args) -> OBJECT {
            OBJECT rem_args = args;
            while (!rem_args.is_null()) {
                OBJECT head = car(rem_args);
                rem_args = cdr(rem_args);

                OBJECT maybe_boolean_obj = head;
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                if (!maybe_boolean_obj.is_boolean()) {
                    std::stringstream ss;
                    ss << "and: expected boolean, received: ";
                    print_obj(head, ss);
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
        {"booleans..."}
    );
    define_builtin_procedure_in_vm(vm,
        "or",
        [](OBJECT args) -> OBJECT {
            OBJECT rem_args = args;
            while (!rem_args.is_null()) {
                OBJECT head = car(rem_args);
                rem_args = cdr(rem_args);

                OBJECT maybe_boolean_obj = head;
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                if (!maybe_boolean_obj.is_boolean()) {
                    std::stringstream ss;
                    ss << "or: expected boolean, received: ";
                    print_obj(head, ss);
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
        {"booleans..."}
    );
}

void bind_standard_arithmetic_procedures(VirtualMachine* vm) {
    bind_standard_variadic_arithmetic_procedure<int_mul_cb, float32_mul_cb, float64_mul_cb>(vm, "*");
    bind_standard_variadic_arithmetic_procedure<int_div_cb, float32_div_cb, float64_div_cb>(vm, "/");
    bind_standard_variadic_arithmetic_procedure<int_rem_cb, float32_rem_cb, float64_rem_cb>(vm, "%");
    bind_standard_variadic_arithmetic_procedure<int_add_cb, float32_add_cb, float64_add_cb>(vm, "+");
    bind_standard_variadic_arithmetic_procedure<int_sub_cb, float32_sub_cb, float64_sub_cb>(vm, "-");
}
template <IntFoldCb int_fold_cb, Float32FoldCb float32_fold_cb, Float64FoldCb float64_fold_cb>
void bind_standard_variadic_arithmetic_procedure(VirtualMachine* vm, char const* const name_str) {
    define_builtin_procedure_in_vm(vm,
        name_str,
        [=](OBJECT args) -> OBJECT {
            // first, ensuring we have at least 1 argument:
            if (args.is_null()) {
                std::stringstream ss;
                ss << "Expected 1 or more arguments to arithmetic operator " << name_str << ": got 0";
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
            size_t arg_count = 0;
            for (
                OBJECT rem_args = args;
                !rem_args.is_null();
                rem_args = cdr(rem_args)
            ) {
                OBJECT operand = car(rem_args);
                ++arg_count;

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
            if (arg_count == 1) {
                // returning identity:
                return car(args);
            }
            else if (!float64_operand_present && !float32_operand_present && arg_count == 2) {
                // adding two integers:
                auto aa = extract_args<2>(args);
                my_ssize_t res = aa[0].as_signed_fixnum();
                int_fold_cb(res, aa[1].as_signed_fixnum());
                return OBJECT::make_integer(res);
            }
            else if (!int_operand_present && !float64_operand_present && arg_count == 2) {
                // adding two float32:
                auto aa = extract_args<2>(args);
                auto res = aa[0].as_float32();
                float32_fold_cb(res, aa[1].as_float32());
                return OBJECT::make_float32(res);
            }
            else if (!int_operand_present && !float32_operand_present && arg_count == 2) {
                // adding two float64:
                auto aa = extract_args<2>(args);
                auto res = aa[0].as_float64();
                float64_fold_cb(res, aa[1].as_float64());
                return OBJECT::make_float64(vm_gc_tfe(vm), res);
            }
            else if (int_operand_present && !float32_operand_present && !float64_operand_present) {
                // compute result from only integers: no floats found
                OBJECT rem_args = args;

                OBJECT first_arg = car(rem_args);
                rem_args = cdr(rem_args);

                my_ssize_t unwrapped_accum = first_arg.as_signed_fixnum();
                for (; !rem_args.is_null(); rem_args = cdr(rem_args)) {
                    OBJECT operand = car(rem_args);
                    my_ssize_t v = operand.as_signed_fixnum();
                    int_fold_cb(unwrapped_accum, v);
                }

                return OBJECT::make_integer(unwrapped_accum);
            }
            else {
                // compute result as a float64:
                OBJECT rem_args = args;

                OBJECT first_arg = car(rem_args);
                rem_args = cdr(rem_args);
                
                double unwrapped_accum = first_arg.to_double();
                for (; !rem_args.is_null(); rem_args = cdr(rem_args)) {
                    OBJECT operand = car(rem_args);
                    my_float_t v = operand.to_double();
                    float64_fold_cb(unwrapped_accum, v);
                }
                
                return OBJECT::make_float64(vm_gc_tfe(vm), unwrapped_accum);
            } 
        },
        {"args..."}
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

///
// Interface
//

void bind_standard_procedures(VirtualMachine* vm) {
    bind_standard_kind_predicates(vm);
    bind_standard_pair_procedures(vm);
    bind_standard_equality_procedures(vm);
    bind_standard_logical_operators(vm);
    bind_standard_list_procedures(vm);
    bind_standard_arithmetic_procedures(vm);
}
