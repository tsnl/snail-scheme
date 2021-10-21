#include "vm.hh"

#include <vector>
#include <string>
#include <sstream>
#include <array>
#include <iostream>
#include <iomanip>
#include <cstdint>
#include <cmath>
#include <cassert>

#include <config/config.hh>
#include "feedback.hh"
#include "object-v2.hh"
#include "printing.hh"
#include "core.hh"

//
// VmExp data: each expression either stores a VM instruction or a constant
// All VmExps are are stored in a flat table in the 'VirtualMachine'.
//  - this ensures traversal during interpretation is of similar efficiency to bytecode with padding
//  - TODO: do we need to traverse this structure to perform GC? cf Ch4
//

enum class VmExpKind: VmExpID {
    Halt,
    Refer,
    Constant,
    Close,
    Test,
    Assign,
    Conti,
    Nuate,
    Frame,
    Argument,
    Apply,
    Return,
    Define,
    // todo: implement a CFFI function call instruction
};
union VmExpArgs {
    struct {} i_halt;
    struct { C_word var; VmExpID x; } i_refer;
    struct { C_word constant; VmExpID x; } i_constant;
    struct { C_word vars; VmExpID body; VmExpID x; } i_close;
    struct { VmExpID next_if_t; VmExpID next_if_f; } i_test;
    struct { C_word var; VmExpID x; } i_assign;
    struct { VmExpID x; } i_conti;
    struct { C_word s; C_word var; } i_nuate;
    struct { VmExpID x; VmExpID ret; } i_frame;
    struct { VmExpID x; } i_argument;
    struct { C_word var; VmExpID next; } i_define;
    struct {} i_apply;
    struct {} i_return_;
};
struct VmExp {
    VmExpKind kind;
    VmExpArgs args;

    VmExp(VmExpKind new_kind)
    :   kind(new_kind),
        args()
    {}
};
static_assert(
    sizeof(VmExp) == 4*sizeof(size_t), 
    "Unexpected sizeof(VmExp)"
);

//
// VmProgram: 
// represents a path of execution in the ordered node graph: just an (s, t) pair corresponding to 1 expression.
//

struct VmProgram {
    VmExpID s;
    VmExpID t;  // must be a 'halt' expression so we can read the accumulator
};

//
// VmFile: a collection of programs-- one per line, and the source code object (may be reused, e.g. 'quote')
//

struct VmFile {
    std::vector<C_word> line_code_objs;
    std::vector<VmProgram> line_programs;
};

//
// VirtualMachine (VM)
//  - stores and constructs VmExps
//  - runs VmExps to `halt`
//  - de-allocates all expressions (and thus, all `Object` instances parsed and possibly reused)
//

typedef void(*IntFoldCb)(C_word& accum, C_word item);
typedef void(*FloatFoldCb)(C_float& accum, C_float item);

class VirtualMachine {
  private:
    struct {
        C_word a;                  // the accumulator
        VmExpID x;                  // the next expression
        C_word e;              // the current environment
        C_word r;                  // value rib; used to compute arguments for 'apply'
        C_word s;     // the current stack
    } m_reg;
    std::vector<VmExp> m_exps;
    std::vector< VmFile > m_files;
    
    C_word m_init_env;
    C_word m_init_var_rib;
    C_word m_init_elt_rib;

    const struct {
        IntStr const quote;
        IntStr const lambda;
        IntStr const if_;
        IntStr const set;
        IntStr const call_cc;
        IntStr const define;
        IntStr const begin;
    } m_builtin_intstr_id_cache;
  public:
    explicit VirtualMachine(size_t reserved_file_count = 32);
    ~VirtualMachine();
  
  // creating VM expressions:
  private:
    std::pair<VmExpID, VmExp&> help_new_vmx(VmExpKind kind);
    VmExpID new_vmx_halt();
    VmExpID new_vmx_refer(C_word var, VmExpID next);
    VmExpID new_vmx_constant(C_word constant, VmExpID next);
    VmExpID new_vmx_close(C_word vars, VmExpID body, VmExpID next);
    VmExpID new_vmx_test(VmExpID next_if_t, VmExpID next_if_f);
    VmExpID new_vmx_assign(C_word var, VmExpID next);
    VmExpID new_vmx_conti(VmExpID x);
    VmExpID new_vmx_nuate(C_word stack, C_word var);
    VmExpID new_vmx_frame(VmExpID x, VmExpID ret);
    VmExpID new_vmx_argument(VmExpID x);
    VmExpID new_vmx_apply();
    VmExpID new_vmx_return();
    VmExpID new_vmx_define(C_word var, VmExpID next);

  // Source code loading + compilation:
  public:
    // add_file eats an std::vector<C_word> containing each line
    void add_file(std::string const& file_name, std::vector<C_word> objs);
  private:
    VmProgram translate_single_line_code_obj(C_word line_code_obj);
    VmExpID translate_code_obj(C_word obj, VmExpID next);
    VmExpID translate_code_obj_pair_list(C_word obj, VmExpID next);
    bool is_tail_vmx(VmExpID vmx_id);

  // Blocking execution functions:
  // Run each expression in each file sequentially on this thread.
  public:
    void sync_execute();

  // Interpreter environment setup:
  public:
    C_word mk_default_root_env();
    void define_builtin_fn(std::string name_str, C_cppcb callback, std::vector<std::string> arg_names);
    template <IntFoldCb int_fold_cb, FloatFoldCb float_fold_cb>
    void define_builtin_variadic_arithmetic_fn(char const* name_str);
    static C_word closure(VmExpID body, C_word env, C_word args);
    static C_word lookup(C_word symbol, C_word env_raw);
    C_word continuation(C_word s);
    C_word extend(C_word e, C_word vars, C_word vals, bool is_binding_variadic);

  // Error functions:
  public:
    void check_vars_list_else_throw(C_word vars);

  // Debug dumps:
  public:
    void dump(std::ostream& out);
    void print_all_exps(std::ostream& out);
    void print_one_exp(VmExpID exp_id, std::ostream& out);
    void dump_all_files(std::ostream& out);
};

//
// ctor/dtor
//

VirtualMachine::VirtualMachine(size_t file_count) 
:   m_reg(),
    m_exps(),
    m_files(),
    m_builtin_intstr_id_cache({
        .quote = intern("quote"),
        .lambda = intern("lambda"),
        .if_ = intern("if"),
        .set = intern("set!"),
        .call_cc = intern("call/cc"),
        .define = intern("define"),
        .begin = intern("begin")
    }),
    m_init_env(C_SCHEME_END_OF_LIST),
    m_init_var_rib(C_SCHEME_END_OF_LIST),
    m_init_elt_rib(C_SCHEME_END_OF_LIST)
{
    m_exps.reserve(4096);
    m_files.reserve(file_count);
}

VirtualMachine::~VirtualMachine() {
    // todo: clean up code object memory-- leaking for now.
    //  - cannot delete `BoolObject` or other singletons
    // for (VmFile const& file: m_files) {
    //     for (C_word o: file.line_code_objs) {
    //         delete o;
    //     }
    // }
}

//
// Creating VM Expressions:
//

std::pair<VmExpID, VmExp&> VirtualMachine::help_new_vmx(VmExpKind kind) {
    auto exp_id = m_exps.size();
    auto& exp_ref = m_exps.emplace_back(kind);
    return {exp_id, exp_ref};
}
VmExpID VirtualMachine::new_vmx_halt() {
    return help_new_vmx(VmExpKind::Halt).first;
}
VmExpID VirtualMachine::new_vmx_refer(C_word var, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Refer);
    auto& args = exp_ref.args.i_refer;
    args.var = var;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_constant(C_word constant, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Constant);
    auto& args = exp_ref.args.i_constant;
    args.constant = constant;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_close(C_word vars, VmExpID body, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Close);
    auto& args = exp_ref.args.i_close;
    args.vars = vars;
    args.body = body;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_test(VmExpID next_if_t, VmExpID next_if_f) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Test);
    auto& args = exp_ref.args.i_test;
    args.next_if_t = next_if_t;
    args.next_if_f = next_if_f;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_assign(C_word var, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Assign);
    auto& args = exp_ref.args.i_assign;
    args.var = var;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_conti(VmExpID x) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Conti);
    auto& args = exp_ref.args.i_conti;
    args.x = x;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_nuate(C_word stack, C_word var) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Nuate);
    auto& args = exp_ref.args.i_nuate;
    args.s = stack;
    args.var = var;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_frame(VmExpID x, VmExpID ret) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Frame);
    auto& args = exp_ref.args.i_frame;
    args.x = x;
    args.ret = ret;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_argument(VmExpID x) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Argument);
    auto& args = exp_ref.args.i_argument;
    args.x = x;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_apply() {
    return help_new_vmx(VmExpKind::Apply).first;
}
VmExpID VirtualMachine::new_vmx_return() {
    return help_new_vmx(VmExpKind::Return).first;
}
VmExpID VirtualMachine::new_vmx_define(C_word var, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Define);
    auto& args = exp_ref.args.i_define;
    args.var = var;
    args.next = next;
    return exp_id;
}

//
// Source code loading + compilation (p. 57 of 'three-imp.pdf')
//

void VirtualMachine::add_file(std::string const& file_name, std::vector<C_word> objs) {
    if (!objs.empty()) {
        // translating each line into a program that terminates with 'halt'
        std::vector<VmProgram> line_programs;
        line_programs.reserve(objs.size());
        for (C_word line_code_obj: objs) {
            VmProgram program = translate_single_line_code_obj(line_code_obj);
            line_programs.push_back(program);
        }

        // storing the input lines and the programs on this VM:
        VmFile new_file = {std::move(objs), line_programs};
        m_files.push_back(std::move(new_file));
    } else {
        warning(std::string("VM: Input file `") + file_name + "` is empty.");
    }
}

VmProgram VirtualMachine::translate_single_line_code_obj(C_word line_code_obj) {
    VmExpID last_exp_id = new_vmx_halt();
    VmExpID first_exp_id = translate_code_obj(line_code_obj, last_exp_id);
    return VmProgram {first_exp_id, last_exp_id};
}
VmExpID VirtualMachine::translate_code_obj(C_word obj, VmExpID next) {
    // iteratively translating this line to a VmProgram
    //  - cf p. 56 of 'three-imp.pdf', §3.4.2: Translation
    if (is_symbol(obj))    { return new_vmx_refer(obj, next); }
    else if (is_pair(obj)) { return translate_code_obj_pair_list(obj, next); }
    else                   { return new_vmx_constant(obj, next); }
}
VmExpID VirtualMachine::translate_code_obj_pair_list(C_word obj, VmExpID next) {
    // retrieving key properties:
    C_word head = c_car(obj);
    C_word args = c_cdr(obj);

    // first, trying to handle a builtin function invocation:
    if (is_symbol(head)) {
        // keyword first argument
        IntStr keyword_symbol_id = C_UNWRAP_SYMBOL(head);

        if (keyword_symbol_id == m_builtin_intstr_id_cache.quote) {
            // quote
            auto quoted = extract_args<1>(args)[0];
            return new_vmx_constant(quoted, next);
        }
        else if (keyword_symbol_id == m_builtin_intstr_id_cache.lambda) {
            // lambda
            auto args_array = extract_args<2>(args);
            auto vars = args_array[0];
            auto body = args_array[1];
            
            check_vars_list_else_throw(vars);

            return new_vmx_close(
                vars,
                translate_code_obj(
                    body,
                    new_vmx_return()
                ),
                next
            );
        }
        else if (keyword_symbol_id == m_builtin_intstr_id_cache.if_) {
            // if
            auto args_array = extract_args<3>(args);
            auto cond_code_obj = args_array[0];
            auto then_code_obj = args_array[1];
            auto else_code_obj = args_array[2];
            return translate_code_obj(
                cond_code_obj,
                new_vmx_test(
                    translate_code_obj(then_code_obj, next),
                    translate_code_obj(else_code_obj, next)
                )
            );
        }
        else if (keyword_symbol_id == m_builtin_intstr_id_cache.set) {
            // set!
            auto args_array = extract_args<2>(args);
            auto var_obj = args_array[0];
            auto set_obj = args_array[1];   // we set the variable to this object, 'set' in past-tense
            // todo: check that 'var_obj' is a symbol
            return translate_code_obj(
                set_obj,
                new_vmx_assign(
                    var_obj,
                    next
                )
            );
        }
        else if (keyword_symbol_id == m_builtin_intstr_id_cache.call_cc) {
            // call/cc
            auto args_array = extract_args<1>(args);
            auto x = args_array[0];
            // todo: check that 'x', the called function, is in fact a procedure.
            auto c = new_vmx_conti(
                new_vmx_argument(
                    translate_code_obj(x, new_vmx_apply())
                )
            );
            return (
                (is_tail_vmx(next)) ?
                c :
                new_vmx_frame(next, c)
            );
        } 
        else if (keyword_symbol_id == m_builtin_intstr_id_cache.define) {
            // define
            auto args_array = extract_args<2>(args);
            auto structural_signature = args_array[0];
            auto body = args_array[1];

            if (structural_signature && is_symbol(structural_signature)) {
                // (define <var> <initializer>)
                return new_vmx_define(
                    structural_signature, 
                    translate_code_obj(
                        body,
                        new_vmx_assign(
                            structural_signature,
                            next
                        )
                    )
                );
            }
            else if (structural_signature && is_pair(structural_signature)) {
                // (define (<fn-name> <arg-vars...>) <initializer>)
                // expands to
                // (define <fn-name> (lambda (<arg-vars) <initializer>))
                auto fn_name = c_car(structural_signature);
                auto arg_vars = c_cdr(structural_signature);
                
                check_vars_list_else_throw(arg_vars);

                if (!is_symbol(fn_name)) {
                    std::stringstream ss;
                    ss << "define: invalid function name: ";
                    print_obj2(fn_name, ss);
                    error(ss.str());
                    throw SsiError();
                }

                // create a lambda, then invoke 'define':
                return new_vmx_define(
                    fn_name,
                    new_vmx_close(
                        arg_vars,
                        translate_code_obj(body, new_vmx_return()),
                        new_vmx_assign(
                            fn_name,
                            next
                        )
                    )
                );
            }

            throw SsiError();
        }
        else if (keyword_symbol_id == m_builtin_intstr_id_cache.begin) {
            // (begin expr ...+)

            // ensuring at least one argument is provided:
            if (args == C_SCHEME_END_OF_LIST) {
                error("begin: expected at least one expression form to evaluate, got 0.");
                throw SsiError();
            }

            // assembling each code object on a stack to translate in reverse order:
            std::vector<C_word> obj_stack;
            obj_stack.reserve(32);
            C_word rem_args = args;
            while (rem_args) {
                obj_stack.push_back(c_car(rem_args));
                rem_args = c_cdr(rem_args);
            }

            // translating:
            VmExpID final_begin_instruction = next;
            while (!obj_stack.empty()) {
                final_begin_instruction = translate_code_obj(obj_stack.back(), final_begin_instruction);
                obj_stack.pop_back();
            }

            return final_begin_instruction;
        }
        else {
            // continue to the branch below...
        }
    }

    // otherwise, handling a function call:
    //  NOTE: the 'car' expression could be a non-symbol, e.g. a lambda expression for an IIFE
    {
        // function call
        VmExpID c = translate_code_obj(head, new_vmx_apply());
        C_word c_args = args;
        while (c_args) {
            c = translate_code_obj(
                c_car(c_args),
                new_vmx_argument(c)
            );
            c_args = c_cdr(c_args);
        }
        if (is_tail_vmx(next)) {
            return c;
        } else {
            return new_vmx_frame(next, c);
        }
    }
}
bool VirtualMachine::is_tail_vmx(VmExpID vmx_id) {
    return m_exps[vmx_id].kind == VmExpKind::Return;
}

// todo: implement printing for VM instructions
// todo: implement execution for VM instructions
// todo: implement a debugger for the VM?
//   - some sort of line associations so our back-trace is meaningful

//
// Blocking execution:
//

void VirtualMachine::sync_execute() {
    // this function is a direct translation of the function `VM` on p. 60 of `three-imp.pdf`, except
    //  - the tail-recursive function is transformed into a loop
    //  - rather than considering any return value, we just execute the script and rely on IO and 
    //    side-effects to provide feedback to the user. Thus, 'halt' is ignored.
    //  - each line object results in a `halt` instruction--
    //      - if `print_each_line` is true, we print the input and output lines to stdout
    //      - NOTE: `print_each_line` is a compile-time-constant-- if false, branches should be optimized out.

    m_reg.e = mk_default_root_env();

    // for each line object in each file...
    for (auto f: m_files) {
        auto line_count = f.line_code_objs.size();
        for (size_t i = 0; i < line_count; i++) {
            // acquiring input:
            C_word input = f.line_code_objs[i];
            VmProgram program = f.line_programs[i];

            // printing input line before execution if desired:
#if CONFIG_PRINT_EACH_LINE_ON_EXECUTION
            {
                std::cout << "snail-scheme> ";
                print_obj2(input, std::cout);
                std::cout << std::endl;
            }
#endif

            // setting start instruction:
            m_reg.x = program.s;

            // running iteratively until 'halt':
            //  - cf `VM` function on p. 60 of `three-imp.pdf`
            bool vm_is_running = true;
            while (vm_is_running) {
                VmExp const& exp = m_exps[m_reg.x];

                // DEBUG ONLY: print each instruction on execution to help trace
                // todo: perhaps include a thread-ID? Some synchronization around IO [basically GIL]
#if CONFIG_PRINT_EACH_INSTRUCTION_ON_EXECUTION
                std::wcout << L"\tVM <- ";
                print_one_exp(m_reg.x, std::cout);
                std::cout << std::endl;
#endif

                switch (exp.kind) {
                    case VmExpKind::Halt: {
                        vm_is_running = false;
                    } break;
                    case VmExpKind::Refer: {
                        m_reg.a = c_car(lookup(exp.args.i_refer.var, m_reg.e));
                        m_reg.x = exp.args.i_refer.x;
                    } break;
                    case VmExpKind::Constant: {
                        m_reg.a = exp.args.i_constant.constant;
                        m_reg.x = exp.args.i_constant.x;
                    } break;
                    case VmExpKind::Close: {
                        m_reg.a = closure(
                            exp.args.i_close.body,
                            m_reg.e,
                            exp.args.i_close.vars
                        );
                        m_reg.x = exp.args.i_close.x;
                    } break;
                    case VmExpKind::Test: {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                        if (!is_bool(m_reg.a)) {
                            std::stringstream ss;
                            ss << "test: expected a `bool` expression in a conditional, received: ";
                            print_obj2(m_reg.a, ss);
                            error(ss.str());
                            throw SsiError();
                        }
#endif
                        if (C_UNWRAP_BOOL(m_reg.a)) {
                            m_reg.x = exp.args.i_test.next_if_t;
                        } else {
                            m_reg.x = exp.args.i_test.next_if_f;
                        }
                    } break;
                    case VmExpKind::Assign: {
                        auto rem_value_rib = lookup(
                            exp.args.i_assign.var,
                            m_reg.e
                        );
                        c_set_car(rem_value_rib, m_reg.a);
                        m_reg.x = exp.args.i_assign.x;
                    } break;
                    case VmExpKind::Conti: {
                        m_reg.a = continuation(m_reg.s);
                        m_reg.x = exp.args.i_conti.x;
                    } break;
                    case VmExpKind::Nuate: {
                        m_reg.a = c_car(lookup(exp.args.i_nuate.var, m_reg.e));
                        m_reg.x = new_vmx_return();
                        m_reg.s = exp.args.i_nuate.s;
                    } break;
                    case VmExpKind::Frame: {
                        m_reg.x = exp.args.i_frame.ret;
                        m_reg.s = c_call_frame(
                            exp.args.i_frame.x,
                            m_reg.e,
                            m_reg.r,
                            m_reg.s
                        );
                        m_reg.r = C_SCHEME_END_OF_LIST;
                    } break;
                    case VmExpKind::Argument: {
                        m_reg.x = exp.args.i_argument.x;
                        m_reg.r = c_cons(m_reg.a, m_reg.r);
                    } break;
                    case VmExpKind::Apply: {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                        if (!c_is_procedure(m_reg.a)) {
                            std::stringstream ss;
                            ss << "apply: expected a procedure, received: ";
                            print_obj2(m_reg.a, ss);
                            ss << std::endl;
                            error(ss.str());
                            throw SsiError();
                        }
#endif
                        if (is_closure(m_reg.a)) {
                            // a Scheme function is called
                            auto a = static_cast<C_word>(m_reg.a);
                            C_word new_e;
                            try {
                                new_e = extend(
                                    c_ref_closure_e(a),
                                    c_ref_closure_vars(a),
                                    m_reg.r,
                                    false
                                );
                            } catch (SsiError const&) {
                                std::stringstream ss;
                                ss << "See applied procedure: ";
                                print_obj2(m_reg.a, ss);
                                more(ss.str());
                                throw;
                            }
                            // m_reg.a = m_reg.a;
                            m_reg.x = c_ref_closure_body(a);
                            m_reg.e = new_e;
                            m_reg.r = C_SCHEME_END_OF_LIST;
                        }
                        else if (is_cpp_callback(m_reg.a)) {
                            // a C++ function is called; assume 'return' is called internally
                            auto a = static_cast<C_word>(m_reg.a);
//                            auto e_prime = extend(a->e(), a->vars(), m_reg.r);
                            auto s_prime = m_reg.s;
                            auto s = c_ref_call_frame_opt_parent(m_reg.s);
                            m_reg.a = c_ref_cpp_callback_cb(a)->operator()(m_reg.r);
                            // leave env unaffected, since after evaluation, we continue with original env
                            // pop the stack frame added by 'Frame'
                            m_reg.x = c_ref_call_frame_x(s_prime);
                            m_reg.e = c_ref_call_frame_e(s_prime);
                            m_reg.r = c_ref_call_frame_r(s_prime);

                            // FIXME: I think this is the correct version, but not what we already have, where 's'
                            //        is left unmodified?
                            //          cf Return below
                            // m_reg.s = c_ref_call_frame_opt_parent(s);
                        }
                        else {
                            error("Invalid callable while type-checks disabled");
                            throw SsiError();
                        }
                    } break;
                    case VmExpKind::Return: {
                        auto s = m_reg.s;
                        // m_reg.a = m_reg.a;
                        m_reg.x = c_ref_call_frame_x(s);
                        m_reg.e = c_ref_call_frame_e(s);
                        m_reg.r = c_ref_call_frame_r(s);
                        m_reg.s = c_ref_call_frame_opt_parent(s);
                    } break;
                    case VmExpKind::Define: {
                        m_reg.x = exp.args.i_define.next;
                        m_reg.e = extend(
                            m_reg.e,
                            c_list(exp.args.i_define.var),
                            c_list(static_cast<C_word>(C_SCHEME_UNBOUND)),
                            false
                        );
                        // DEBUG:
                        // auto def_name = static_cast<C_word>(exp.args.i_define.var)->name();
                        // std::cout << "define: " << interned_string(def_name) << ": ";
                        // print_obj(m_reg.a, std::cout);
                        // std::cout << std::endl;
                        // std::cout << "  - now, env is: ";
                        // print_obj(m_reg.e, std::cout);
                        // std::cout << std::endl;
                    } break;
                    // default: {
                    //     std::stringstream ss;
                    //     ss << "NotImplemented: running interpreter for instruction VmExpKind::?";
                    //     error(ss.str());
                    //     throw SsiError();
                    // }
                }
            }

            // printing line output if desired:
#if CONFIG_PRINT_EACH_LINE_ON_EXECUTION
            {
                std::cout << "            => ";
                print_obj2(m_reg.a, std::cout);
                std::cout << std::endl;
            }
#endif
        }
    }
}

inline void int_mul_cb(C_word& accum, C_word item) { accum *= item; }
inline void int_div_cb(C_word& accum, C_word item) { accum /= item; }
inline void int_rem_cb(C_word& accum, C_word item) { accum %= item; }
inline void int_add_cb(C_word& accum, C_word item) { accum += item; }
inline void int_sub_cb(C_word& accum, C_word item) { accum -= item; }
inline void float_mul_cb(C_float& accum, C_float item) { accum *= item; }
inline void float_div_cb(C_float& accum, C_float item) { accum /= item; }
inline void float_rem_cb(C_float& accum, C_float item) { accum = fmod(accum, item); }
inline void float_add_cb(C_float& accum, C_float item) { accum += item; }
inline void float_sub_cb(C_float& accum, C_float item) { accum -= item; }

C_word VirtualMachine::mk_default_root_env() {
    // definitions:
    define_builtin_fn(
        "cons", 
        [](C_word args) -> C_word {
            auto aa = extract_args<2>(args);
            return c_cons(aa[0], aa[1]);
        }, 
        {"ar", "dr"}
    );
    define_builtin_fn(
        "car", 
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
            if (!is_pair(aa[0])) {
                std::stringstream ss;
                ss << "car: expected pair argument, received: ";
                print_obj2(aa[0], ss);
                error(ss.str());
                throw SsiError();
            }
#endif
            return c_car(aa[0]);
        }, 
        {"pair"}
    );
    define_builtin_fn(
        "cdr", 
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
            if (!is_pair(aa[0])) {
                std::stringstream ss;
                ss << "cdr: expected pair argument, received: ";
                print_obj2(aa[0], ss);
                error(ss.str());
                throw SsiError();
            }
#endif
            return c_cdr(aa[0]);
        }, 
        {"pair"}
    );
    define_builtin_fn(
        "boolean?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_is_bool(aa[0]);
        },
        {"obj"}
    );
    define_builtin_fn(
        "null?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_is_eol(aa[0]);
        },
        {"obj"}
    );
    define_builtin_fn(
        "pair?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_is_pair(aa[0]);
        },
        {"obj"}
    );
    define_builtin_fn(
        "procedure?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_is_procedure(aa[0]);
        },
        {"obj"}
    );
    define_builtin_fn(
        "symbol?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_is_symbol(aa[0]);
        },
        {"obj"}
    );
    define_builtin_fn(
        "integer?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_is_integer(aa[0]);
        },
        {"obj"}
    );
    define_builtin_fn(
        "real?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_is_flonum(aa[0]);
        },
        {"obj"}
    );
    define_builtin_fn(
        "number?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_boolean(is_flonum(aa[0]) || is_integer(aa[0]));
        },
        {"obj"}
    );
    define_builtin_fn(
        "string?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_is_string(aa[0]);
        },
        {"obj"}
    );
    define_builtin_fn(
        "vector?",
        [](C_word args) -> C_word {
            auto aa = extract_args<1>(args);
            return c_is_vector(aa[0]);
        },
        {"obj"}
    );

    //
    //
    ///
    //
    //
    //
    //
    //
    //
    // FIXME: the remaining builtin functions are stubbed-- need to implement more of object-v2 based on v1.
    //  - the rest of this file will not compile
    //
    //
    //
    //
    //
    //
    //
    //
    //

//    define_builtin_fn(
//        "=",
//        [](C_word args) -> C_word {
//            auto aa = extract_args<2>(args);
//            return c_is_eqn(aa[0], aa[1]);
//        },
//        {"lt-arg", "rt-arg"}
//    );
//    define_builtin_fn(
//        "eq?",
//        [](C_word args) -> C_word {
//            auto aa = extract_args<2>(args);
//            return boolean(is_eq(aa[0], aa[1]));
//        },
//        {"lt-arg", "rt-arg"}
//    );
//    define_builtin_fn(
//        "eqv?",
//        [](C_word args) -> C_word {
//            auto aa = extract_args<2>(args);
//            return boolean(is_eqv(aa[0], aa[1]));
//        },
//        {"lt-arg", "rt-arg"}
//    );
//    define_builtin_fn(
//        "equal?",
//        [](C_word args) -> C_word {
//            auto aa = extract_args<2>(args);
//            return boolean(is_equal(aa[0], aa[1]));
//        },
//        {"lt-arg", "rt-arg"}
//    );
//    define_builtin_fn(
//        "list",
//        [](C_word args) -> C_word {
//            return args;
//        },
//        {"items..."}
//    );
//    define_builtin_fn(
//        "and",
//        [](C_word args) -> C_word {
//            C_word rem_args = args;
//            while (rem_args) {
//                C_word head = car(rem_args);
//                rem_args = cdr(rem_args);
//
//                C_word maybe_boolean_obj = head;
//#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
//                if (maybe_boolean_obj->kind() != ObjectKind::Boolean) {
//                    std::stringstream ss;
//                    ss << "and: expected boolean, received: ";
//                    print_obj(head, ss);
//                    error(ss.str());
//                    throw SsiError();
//                }
//#endif
//                C_word boolean_obj = maybe_boolean_obj;
//                if (boolean_obj == BoolObject::f) {
//                    return BoolObject::f;
//                }
//            }
//            return BoolObject::t;
//        },
//        {"booleans..."}
//    );
//    define_builtin_fn(
//        "or",
//        [](C_word args) -> C_word {
//            C_word rem_args = args;
//            while (rem_args) {
//                C_word head = car(rem_args);
//                rem_args = cdr(rem_args);
//
//                C_word maybe_boolean_obj = head;
//#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
//                if (maybe_boolean_obj->kind() != ObjectKind::Boolean) {
//                    std::stringstream ss;
//                    ss << "or: expected boolean, received: ";
//                    print_obj(head, ss);
//                    error(ss.str());
//                    throw SsiError();
//                }
//#endif
//                C_word boolean_obj = maybe_boolean_obj;
//                if (boolean_obj == BoolObject::t) {
//                    return BoolObject::t;
//                }
//            }
//            return BoolObject::f;
//        },
//        {"booleans..."}
//    );
//    define_builtin_variadic_arithmetic_fn<int_mul_cb, float_mul_cb>("*");
//    define_builtin_variadic_arithmetic_fn<int_div_cb, float_div_cb>("/");
//    define_builtin_variadic_arithmetic_fn<int_rem_cb, float_rem_cb>("%");
//    define_builtin_variadic_arithmetic_fn<int_add_cb, float_add_cb>("+");
//    define_builtin_variadic_arithmetic_fn<int_sub_cb, float_sub_cb>("-");
    // todo: define more builtin functions here

    // finalizing the rib-pair:
    C_word rib_pair = c_cons(m_init_var_rib, m_init_elt_rib);

    // creating a fresh env:
    m_init_env = c_cons(rib_pair, m_init_env);

    // (DEBUG:) printing env after construction:
    // print_obj(env, std::cerr);

    return m_init_env;
}

void VirtualMachine::define_builtin_fn(
    std::string name_str, 
    C_cppcb callback, 
    std::vector<std::string> arg_names
) {
    C_word var_obj = c_symbol(intern(std::move(name_str)));
    C_word vars_list = C_SCHEME_END_OF_LIST;
    for (size_t i = 0; i < arg_names.size(); i++) {
        vars_list = c_cons(c_symbol(intern(arg_names[i])), vars_list);
    }
    C_word elt_obj = c_cpp_callback(callback, m_init_env, vars_list);
    m_init_var_rib = c_cons(var_obj, m_init_var_rib);
    m_init_elt_rib = c_cons(elt_obj, m_init_elt_rib);
}

template <IntFoldCb int_fold_cb, FloatFoldCb float_fold_cb>
void VirtualMachine::define_builtin_variadic_arithmetic_fn(char const* const name_str) {
    define_builtin_fn(
        name_str,
        [=](C_word args) -> C_word {
            // first, ensuring we have at least 1 argument:
            if (!args) {
                std::stringstream ss;
                ss << "Expected 1 or more arguments to arithmetic operator " << name_str << ": got 0";
                error(ss.str());
                throw SsiError();
            }

            // next, determining the kind of the result:
            //  - this is accomplished by performing a linear scan through the arguments
            //  - though inefficient, this ironically improves throughput, presumably by loading cache lines 
            //    containing each operand before 'load'
            bool float_operand_present = false;
            bool int_operand_present = false;
            size_t arg_count = 0;
            for (
                C_word rem_args = args;
                rem_args;
                rem_args = c_cdr(rem_args)
            ) {
                C_word operand = c_car(rem_args);
                ++arg_count;

                if (is_flonum(operand)) {
                    float_operand_present = true;
                }
                else if (is_integer(operand)) {
                    int_operand_present = true;
                }
                else {
                    // error:
                    std::stringstream ss;
                    ss << "Invalid argument to arithmetic operator " << name_str << ": ";
                    print_obj2(operand, ss);
                    error(ss.str());
                    throw SsiError();
                }
            }

            // next, computing the result of this operation:
            // NOTE: computation broken into several 'hot paths' for frequent operations.
            if (arg_count == 1) {
                // returning identity:
                return c_car(args);
            }
            else if (!float_operand_present && arg_count == 2) {
                // adding two integers:
                auto aa = extract_args<2>(args);
                auto res = C_UNWRAP_INT(aa[0]);
                int_fold_cb(res, C_UNWRAP_INT(aa[1]));
                return res;
            }
            else if (!int_operand_present && arg_count == 2) {
                // adding two floats:
                auto aa = extract_args<2>(args);
                auto res = unwrap_flonum(aa[0]);
                float_fold_cb(res, unwrap_flonum(aa[1]));
                return res;
            }
            else if (float_operand_present && int_operand_present) {
                // compute result as a float, mixed int and float:
                C_word rem_args = args;

                C_word first_arg = c_car(rem_args);
                rem_args = c_cdr(rem_args);

                C_float unwrapped_accum;
                if (is_integer(first_arg)) {
                    // static-cast integer into a float to init accum:
                    unwrapped_accum = static_cast<C_float>(C_UNWRAP_INT(first_arg));
                } else {
                    // init accum with first-arg directly:
                    unwrapped_accum = unwrap_flonum(first_arg);
                }
                for (; rem_args; rem_args = c_cdr(rem_args)) {
                    C_word operand = c_car(rem_args);
                    C_float v;
                    if (is_integer(operand)) {
                        v = static_cast<C_float>(C_UNWRAP_INT(operand));
                    } else {
                        // must be a float-- checked before.
                        v = unwrap_flonum(operand);
                    }
                    float_fold_cb(unwrapped_accum, v);
                }
                
                return c_flonum(unwrapped_accum);
            } 
            else if (float_operand_present) {
                // compute result from only floats: no integers found

                C_word rem_args = args;

                C_word first_arg = c_car(rem_args);
                rem_args = c_cdr(rem_args);

                C_float unwrapped_accum = unwrap_flonum(first_arg);
                for (; rem_args; rem_args = c_cdr(rem_args)) {
                    C_word operand = c_car(rem_args);
                    // must be a float-- checked before.
                    C_float v = unwrap_flonum(operand);
                    float_fold_cb(unwrapped_accum, v);
                }
                
                return c_flonum(unwrapped_accum);
            }
            else {
                // compute result from only integers: no floats found
                C_word rem_args = args;

                C_word first_arg = c_car(rem_args);
                rem_args = c_cdr(rem_args);

                int64_t unwrapped_accum = C_UNWRAP_INT(first_arg);
                for (; rem_args; rem_args = c_cdr(rem_args)) {
                    C_word operand = c_car(rem_args);
                    // 'v' must be an integer-- checked before.
                    C_word v = C_UNWRAP_INT(operand);
                    int_fold_cb(unwrapped_accum, v);
                }

                return C_WRAP_INT(unwrapped_accum);
            }
        },
        {"args..."}
    );
}

C_word VirtualMachine::closure(VmExpID body, C_word env, C_word vars) {
    return c_closure(body, env, vars);
}

C_word VirtualMachine::lookup(C_word symbol, C_word env_raw) {
    if (env_raw == C_SCHEME_END_OF_LIST) {
        std::stringstream ss;
        ss << "lookup: symbol used, but undefined: ";
        print_obj2(symbol, ss);
        error(ss.str());
        throw SsiError();
    }

    // we can cast the 'env' to a PairObject since it is a part of our runtime.
    auto env = static_cast<C_word>(env_raw);

    if (!is_symbol(symbol)) {
        std::stringstream ss;
        ss << "lookup: expected query object to be a variable name, received: ";
        print_obj2(symbol, ss);
        error(ss.str());
        throw SsiError();
    } else {
        IntStr sym_name = C_UNWRAP_SYMBOL(symbol);

        // iterating through ribs in the environment:
        // the environment is a 'list of pairs of lists'
        //  - each pair of lists is called a rib-pair or 'ribs'
        //  - each list in the pair is a named rib-- either the value rib or named rib
        for (
            C_word rem_ribs = env;
            rem_ribs;
            rem_ribs = c_cdr(rem_ribs)
        ) {
            auto rib_pair = c_car(rem_ribs);
            auto variable_rib = c_car(rib_pair);
            auto value_rib = c_cdr(rib_pair);

            for (
                C_word
                    rem_variable_rib = variable_rib,
                    rem_value_rib = value_rib;
                rem_value_rib != C_SCHEME_END_OF_LIST;
                ((rem_variable_rib = c_cdr(rem_variable_rib)),
                 (rem_value_rib = c_cdr(rem_value_rib)))
            ) {
                assert(rem_variable_rib && "Expected rem_variable_rib to be non-null with rem_value_rib");
                auto variable_rib_head = c_car(rem_variable_rib);
                if (C_UNWRAP_SYMBOL(variable_rib_head) == sym_name) {
                    // return the remaining value rib so we can reuse for 'set'
                    return rem_value_rib;
                }
            }
        }

        // lookup failed:
        {
            std::stringstream ss;
            ss << "Lookup failed: symbol used but not defined: ";
            print_obj2(symbol, ss);
            error(ss.str());
            throw SsiError();
        }
    }
}

C_word VirtualMachine::continuation(C_word s) {
    static C_word nuate_var = c_symbol(intern("v"));
    return closure(new_vmx_nuate(s, nuate_var), C_SCHEME_END_OF_LIST, c_list(nuate_var));
}

C_word VirtualMachine::extend(C_word e, C_word vars, C_word vals, bool is_binding_variadic) {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
    // fixme: can optimize by iterating through in parallel
    auto var_count = count_list_items(vars);
    auto val_count = count_list_items(vals);
    if (var_count < val_count || (!is_binding_variadic && var_count > val_count)) {
        std::stringstream ss;
        ss  << "Expected "
            << var_count << (is_binding_variadic ? " or more " : " ")
            << "argument(s), received "
            << val_count << std::endl;

        ss << "- vars: ";
        print_obj2(vars, ss);
        ss << std::endl;

        ss << "- vals: ";
        print_obj2(vals, ss);
        ss << std::endl;

        error(ss.str());

        throw SsiError();
    }
#endif
    return c_cons(c_cons(vars, vals), e);
}

//
// Error functions:
//

void VirtualMachine::check_vars_list_else_throw(C_word vars) {
    C_word rem_vars = vars;
    while (rem_vars) {
        C_word head = c_car(rem_vars);
        rem_vars = c_cdr(rem_vars);

        if (is_symbol(head)) {
            std::stringstream ss;
            ss << "Invalid variable list for lambda: expected symbol, got: ";
            print_obj2(head, ss);
            ss << std::endl;
            error(ss.str());
            throw SsiError();
        }
    }
}

//
// VM dumps:
//

void VirtualMachine::dump(std::ostream& out) {
    out << "[Expression Table]" << std::endl;
    print_all_exps(out);
    
    out << "[File Table]" << std::endl;
    dump_all_files(out);
}
void VirtualMachine::print_all_exps(std::ostream& out) {
    size_t pad_w = static_cast<size_t>(std::ceil(std::log(1+m_exps.size()) / std::log(10)));
    for (size_t index = 0; index < m_exps.size(); index++) {
        out << "  [";
        out << std::setfill('0') << std::setw(pad_w) << index;
        out << "] ";

        print_one_exp(index, out);
        
        out << std::endl;
    }
}
void VirtualMachine::print_one_exp(VmExpID exp_id, std::ostream& out) {
    auto exp = m_exps[exp_id];
    out << "(";
    switch (exp.kind) {
        case VmExpKind::Halt: {
            out << "halt";
        } break;
        case VmExpKind::Refer: {
            out << "refer ";
            print_obj2(exp.args.i_refer.var, out);
            out << ' ';
            out << "#:vmx " << exp.args.i_refer.x;
        } break;
        case VmExpKind::Constant: {
            out << "constant ";
            print_obj2(exp.args.i_constant.constant, out);
            out << ' ';
            out << "#:vmx " << exp.args.i_constant.x;
        } break;
        case VmExpKind::Close: {
            out << "close ";
            print_obj2(exp.args.i_refer.var, out);
            out << ' ';
            out << "#:vmx " << exp.args.i_refer.x;
        } break;
        case VmExpKind::Test: {
            out << "test "
                << "#:vmx " << exp.args.i_test.next_if_t << ' '
                << "#:vmx " << exp.args.i_test.next_if_f;
        } break;
        case VmExpKind::Assign: {
            out << "assign ";
            print_obj2(exp.args.i_assign.var, out);
            out << ' ';
            out << "#:vmx " << exp.args.i_assign.x;
        } break;
        case VmExpKind::Conti: {
            out << "conti ";
            out << "#:vmx " << exp.args.i_conti.x;
        } break;
        case VmExpKind::Nuate: {
            out << "nuate ";
            print_obj2(exp.args.i_nuate.var, out);
            out << ' '
                << "#:vmx " << exp.args.i_nuate.s;
        } break;
        case VmExpKind::Frame: {
            out << "frame "
                << "#:vmx " << exp.args.i_frame.x << ' '
                << "#:vmx " << exp.args.i_frame.ret;
        } break;
        case VmExpKind::Argument: {
            out << "argument "
                << "#:vmx " << exp.args.i_argument.x;
        } break;
        case VmExpKind::Apply: {
            out << "apply";
        } break;
        case VmExpKind::Return: {
            out << "return";
        } break;
        case VmExpKind::Define: {
            out << "define ";
            print_obj2(exp.args.i_define.var, out);
            out << " "
                << "#:vmx " << exp.args.i_define.next;
        } break;
    }
    out << ")";
}
void VirtualMachine::dump_all_files(std::ostream& out) {
    for (size_t i = 0; i < m_files.size(); i++) {
        out << "  " "- file #:" << 1+i << std::endl;
        auto f = m_files[i];

        for (size_t j = 0; j < f.line_code_objs.size(); j++) {
            C_word line_code_obj = f.line_code_objs[j];
            VmProgram program = f.line_programs[j];

            out << "    " "  > ";
            print_obj2(line_code_obj, out);
            out << std::endl;
            out << "    " " => " << "(#:vmx" << program.s << " #:vmx" << program.t << ")";
            out << std::endl;
        }
    }
}

//
//
// Interface:
//
//

VirtualMachine* create_vm() {
    return new VirtualMachine(); 
}

void add_file_to_vm(VirtualMachine* vm, std::string const& file_name, std::vector<C_word> objs) {
    // todo: iteratively compile each statement, such that...
    //  - i < len(objs)-1 => 'next' of last statement is first instruction of (i+1)th object
    //  - i = len(objs)-1 => 'next' of last statement is 'halt'
    vm->add_file(file_name, std::move(objs));
}

void sync_execute_vm(VirtualMachine* vm) {
    vm->sync_execute();
}

void dump_vm(VirtualMachine* vm, std::ostream& out) {
    vm->dump(out);
}