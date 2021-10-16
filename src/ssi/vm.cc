#include "vm.hh"

#include <vector>
#include <string>
#include <sstream>
#include <array>
#include <iostream>
#include <iomanip>
#include <cstdint>
#include <cmath>

#include <config/config.hh>
#include "feedback.hh"
#include "object.hh"
#include "printing.hh"

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
    struct { Object* var; VmExpID x; } i_refer;
    struct { Object* constant; VmExpID x; } i_constant;
    struct { Object* vars; VmExpID body; VmExpID x; } i_close;
    struct { VmExpID next_if_t; VmExpID next_if_f; } i_test;
    struct { Object* var; VmExpID x; } i_assign;
    struct { VmExpID x; } i_conti;
    struct { VMA_CallFrameObject* s; Object* var; } i_nuate;
    struct { VmExpID x; VmExpID ret; } i_frame;
    struct { VmExpID x; } i_argument;
    struct { Object* var; VmExpID next; } i_define;
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
    std::vector<Object*> line_code_objs;
    std::vector<VmProgram> line_programs;
};

//
// VirtualMachine (VM)
//  - stores and constructs VmExps
//  - runs VmExps to `halt`
//  - de-allocates all expressions (and thus, all `Object` instances parsed and possibly reused)
//

class VirtualMachine {
  private:
    struct {
        Object* a;                  // the accumulator
        VmExpID x;                  // the next expression
        PairObject* e;              // the current environment
        Object* r;                  // value rib; used to compute arguments for 'apply'
        VMA_CallFrameObject* s;     // the current stack
    } m_reg;
    std::vector<VmExp> m_exps;
    std::vector< VmFile > m_files;

    const struct {
        IntStr const quote;
        IntStr const lambda;
        IntStr const if_;
        IntStr const set;
        IntStr const call_cc;
        IntStr const define;
    } m_builtin_intstr_id_cache;
  public:
    explicit VirtualMachine(size_t reserved_file_count = 32);
    ~VirtualMachine();
  
  // creating VM expressions:
  private:
    std::pair<VmExpID, VmExp&> help_new_vmx(VmExpKind kind);
    VmExpID new_vmx_halt();
    VmExpID new_vmx_refer(Object* var, VmExpID next);
    VmExpID new_vmx_constant(Object* constant, VmExpID next);
    VmExpID new_vmx_close(Object* vars, VmExpID body, VmExpID next);
    VmExpID new_vmx_test(VmExpID next_if_t, VmExpID next_if_f);
    VmExpID new_vmx_assign(Object* var, VmExpID next);
    VmExpID new_vmx_conti(VmExpID x);
    VmExpID new_vmx_nuate(VMA_CallFrameObject* stack, Object* var);
    VmExpID new_vmx_frame(VmExpID x, VmExpID ret);
    VmExpID new_vmx_argument(VmExpID x);
    VmExpID new_vmx_apply();
    VmExpID new_vmx_return();
    VmExpID new_vmx_define(Object* var, VmExpID next);

  // TODO: creating VM stacks
  private:
    
  // Source code loading + compilation:
  public:
    // add_file eats an std::vector<Object*> containing each line
    void add_file(std::string const& file_name, std::vector<Object*> objs);
  private:
    VmProgram translate_single_line_code_obj(Object* line_code_obj);
    VmExpID translate_code_obj(Object* obj, VmExpID next);
    VmExpID translate_code_obj__pair_list(PairObject* obj, VmExpID next);
    bool is_tail_vmx(VmExpID vmx_id);

  // Blocking execution functions:
  // Run each expression in each file sequentially on this thread.
  public:
    template <bool print_each_line>
    void sync_execute();

  // Interpreter environment setup:
  public:
    static PairObject* mk_default_root_env();
    static VMA_ClosureObject* closure(VmExpID body, PairObject* env, Object* args);
    static PairObject* lookup(Object* symbol, Object* env_raw);
    VMA_ClosureObject* continuation(VMA_CallFrameObject* s);
    PairObject* extend(PairObject* e, Object* vars, Object* vals);

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
        .define = intern("define")
    })
{
    m_exps.reserve(4096);
    m_files.reserve(file_count);
}

VirtualMachine::~VirtualMachine() {
    // todo: clean up code object memory-- leaking for now.
    //  - cannot delete `BoolObject` or other singletons
    // for (VmFile const& file: m_files) {
    //     for (Object* o: file.line_code_objs) {
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
VmExpID VirtualMachine::new_vmx_refer(Object* var, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Refer);
    auto& args = exp_ref.args.i_refer;
    args.var = var;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_constant(Object* constant, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Constant);
    auto& args = exp_ref.args.i_constant;
    args.constant = constant;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_close(Object* vars, VmExpID body, VmExpID next) {
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
VmExpID VirtualMachine::new_vmx_assign(Object* var, VmExpID next) {
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
VmExpID VirtualMachine::new_vmx_nuate(VMA_CallFrameObject* stack, Object* var) {
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
VmExpID VirtualMachine::new_vmx_define(Object* var, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Define);
    auto& args = exp_ref.args.i_define;
    args.var = var;
    args.next = next;
    return exp_id;
}

//
// Creating VM stacks
//

// todo: implement me

//
// Source code loading + compilation (p. 57 of 'three-imp.pdf')
//

void VirtualMachine::add_file(std::string const& file_name, std::vector<Object*> objs) {
    if (!objs.empty()) {
        // translating each line into a program that terminates with 'halt'
        std::vector<VmProgram> line_programs;
        line_programs.reserve(objs.size());
        for (Object* line_code_obj: objs) {
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

VmProgram VirtualMachine::translate_single_line_code_obj(Object* line_code_obj) {
    VmExpID last_exp_id = new_vmx_halt();
    VmExpID first_exp_id = translate_code_obj(line_code_obj, last_exp_id);
    return VmProgram {first_exp_id, last_exp_id};
}
VmExpID VirtualMachine::translate_code_obj(Object* obj, VmExpID next) {
    // todo: iteratively translate this line to a VmProgram
    //  - cf p. 56 of 'three-imp.pdf', §3.4.2: Translation
    auto obj_kind = obj->kind();
    switch (obj_kind) {
        case ObjectKind::Symbol: {
            return new_vmx_refer(obj, next);
        }
        case ObjectKind::Pair: {
            return translate_code_obj__pair_list(static_cast<PairObject*>(obj), next);
        }
        default: {
            return new_vmx_constant(obj, next);
        }
    }
}
VmExpID VirtualMachine::translate_code_obj__pair_list(PairObject* obj, VmExpID next) {
    // retrieving key properties:
    Object* head = obj->car();
    Object* args = obj->cdr();

    // first, trying to handle a builtin function invocation:
    if (head->kind() == ObjectKind::Symbol) {
        // keyword first argument
        auto sym_head = static_cast<SymbolObject*>(head);
        auto keyword_symbol_id = sym_head->name();

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
            // todo: check that 'vars' is a list of symbols
            //  - cf `define`
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

            if (structural_signature && structural_signature->kind() == ObjectKind::Symbol) {
                // (define <var> <initializer>)
                return new_vmx_define(structural_signature, next);
            }
            else if (structural_signature && structural_signature->kind() == ObjectKind::Pair) {
                // (define (<fn-name> <arg-vars...>) <initializer>)
                // desugars to 
                // (define <fn-name> (lambda (<arg-vars) <initializer>))
                auto fn_name = car(structural_signature);
                auto arg_vars = cdr(structural_signature);
                // todo: check that arg_vars are a list of SymbolObjects
                //  - cf 'lambda'
                if (!fn_name || fn_name->kind() != ObjectKind::Symbol) {
                    std::stringstream ss;
                    ss << "define: invalid function name: ";
                    print_obj(fn_name, ss);
                    error(ss.str());
                    throw SsiError();
                }
                return new_vmx_close(
                    arg_vars,
                    translate_code_obj(body, new_vmx_return()),
                    new_vmx_define(fn_name, next)
                );
            }

            throw SsiError();
        }
        else {
            // continue to the branch below...
        }
    }

    // otherwise, handling a function call:
    //  NOTE: the 'car' expression could be a non-symbol, e.g. a lambda expression for an IIFE
    {
        // function call
        VmExpID c = translate_code_obj(
            head,
            new_vmx_apply()
        );
        Object* c_args = args;
        while (c_args) {
            c = translate_code_obj(
                car(c_args),
                new_vmx_argument(c)
            );
            c_args = cdr(c_args);
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

template <bool print_each_line>
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
            Object* input = f.line_code_objs[i];
            VmProgram program = f.line_programs[i];

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
                        m_reg.a = lookup(exp.args.i_refer.var, m_reg.e)->car();
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
                        if (!m_reg.a || m_reg.a->kind() != ObjectKind::Boolean) {
                            std::stringstream ss;
                            ss << "test: expected a `bool` expression in a conditional, received: ";
                            print_obj(m_reg.a, ss);
                            error(ss.str());
                            throw SsiError();
                        }
#endif
                        if (m_reg.a == BoolObject::t) {
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
                        rem_value_rib->set_car(m_reg.a);
                        m_reg.x = exp.args.i_assign.x;
                    } break;
                    case VmExpKind::Conti: {
                        m_reg.a = continuation(m_reg.s);
                        m_reg.x = exp.args.i_conti.x;
                    } break;
                    case VmExpKind::Nuate: {
                        m_reg.a = car(lookup(exp.args.i_nuate.var, m_reg.e));
                        m_reg.x = new_vmx_return();
                        m_reg.s = exp.args.i_nuate.s;
                    } break;
                    case VmExpKind::Frame: {
                        m_reg.x = exp.args.i_frame.ret;
                        m_reg.r = nullptr;
                        m_reg.s = new VMA_CallFrameObject(
                            exp.args.i_frame.x,
                            m_reg.e,
                            m_reg.r,
                            m_reg.s
                        );
                    } break;
                    case VmExpKind::Argument: {
                        m_reg.x = exp.args.i_argument.x;
                        m_reg.r = cons(m_reg.a, m_reg.r);
                    } break;
                    case VmExpKind::Apply: {
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                        if (m_reg.a->kind() != ObjectKind::VMA_Closure) {
                            std::stringstream ss;
                            ss << "apply: expected a 'closure' instance in m_reg.a, received: ";
                            print_obj(m_reg.a, ss);
                            ss << std::endl;
                            error(ss.str());
                            throw SsiError();
                        }
#endif
                        auto a = static_cast<VMA_ClosureObject*>(m_reg.a);
                        // m_reg.a = m_reg.a;
                        m_reg.x = a->body();
                        m_reg.e = extend(a->e(), a->vars(), m_reg.r);
                        m_reg.r = nullptr;
                    } break;
                    case VmExpKind::Return: {
                        auto s = m_reg.s;
                        // m_reg.a = m_reg.a;
                        m_reg.x = s->x();
                        m_reg.e = s->e();
                        m_reg.r = s->r();
                        m_reg.s = s->parent();
                    } break;
                    case VmExpKind::Define: {
                        m_reg.x = exp.args.i_define.next;
                        m_reg.e = extend(m_reg.e, list(exp.args.i_define.var), list(m_reg.a));
                    } break;
                    // default: {
                    //     std::stringstream ss;
                    //     ss << "NotImplemented: running interpreter for instruction VmExpKind::?";
                    //     error(ss.str());
                    //     throw SsiError();
                    // }
                }
            }

            // printing if desired:
            if (print_each_line) {
                std::cout << "  > ";
                print_obj(input, std::cout);
                std::cout << std::endl;

                std::cout << " => ";
                print_obj(m_reg.a, std::cout);
                std::cout << std::endl;
            }
        }
    }
}

PairObject* VirtualMachine::mk_default_root_env() {
    auto env = nullptr;

    // todo: define builtins, e.g. car/cdr, is___?, etc.
    //  - each 'rib' is a pair of 'elements' and 'variables' lists

    return env;
}

VMA_ClosureObject* VirtualMachine::closure(VmExpID body, PairObject* env, Object* vars) {
    return new VMA_ClosureObject(body, env, vars);
}

PairObject* VirtualMachine::lookup(Object* symbol, Object* env_raw) {
    if (env_raw == nullptr) {
        std::stringstream ss;
        ss << "lookup: symbol used, but undefined: ";
        print_obj(symbol, ss);
        error(ss.str());
        throw SsiError();
    }

    // we can cast the 'env' to a PairObject since it is a part of our runtime.
    auto env = static_cast<PairObject*>(env_raw);

    if (symbol->kind() != ObjectKind::Symbol) {
        std::stringstream ss;
        ss << "lookup: expected query object to be a variable name, received: ";
        print_obj(symbol, ss);
        error(ss.str());
        throw SsiError();
    } else {
        IntStr sym_name = static_cast<SymbolObject*>(symbol)->name();

        // iterating through ribs in the environment:
        // the environment is a 'list of pairs of lists'
        //  - each pair of lists is called a rib-pair or 'ribs'
        //  - each list in the pair is a named rib-- either the value rib or named rib
        for (
            PairObject* rem_ribs = env;
            rem_ribs;
            rem_ribs = static_cast<PairObject*>(rem_ribs->cdr())
        ) {
            auto rib_pair = static_cast<PairObject*>(rem_ribs->car());
            auto variable_rib = static_cast<PairObject*>(rib_pair->car());
            auto value_rib = static_cast<PairObject*>(rib_pair->cdr());

            for (
                PairObject
                    *rem_variable_rib = variable_rib,
                    *rem_value_rib = value_rib;
                rem_value_rib;
                ((rem_variable_rib = static_cast<PairObject*>(rem_variable_rib->cdr())),
                 (rem_value_rib = static_cast<PairObject*>(rem_value_rib->cdr())))
            ) {
                auto variable_rib_head = static_cast<SymbolObject*>(rem_variable_rib->car());
                if (variable_rib_head->name() == sym_name) {
                    // return the remaining value rib so we can reuse for 'set'
                    return rem_value_rib;
                }
            }
        }

        // lookup failed:
        {
            std::stringstream ss;
            ss << "Lookup failed: symbol used but not defined: ";
            print_obj(symbol, ss);
            error(ss.str());
            throw SsiError();
        }
    }
}

VMA_ClosureObject* VirtualMachine::continuation(VMA_CallFrameObject* s) {
    static Object* nuate_var = new SymbolObject(intern("v"));
    return closure(new_vmx_nuate(s, nuate_var), nullptr, list(nuate_var));
}

PairObject* VirtualMachine::extend(PairObject* e, Object* vars, Object* vals) {
    return cons(cons(vars, vals), e);
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
            print_obj(exp.args.i_refer.var, out);
            out << ' ';
            out << "vmx:" << exp.args.i_refer.x;
        } break;
        case VmExpKind::Constant: {
            out << "constant ";
            print_obj(exp.args.i_constant.constant, out);
            out << ' ';
            out << "vmx:" << exp.args.i_constant.x;
        } break;
        case VmExpKind::Close: {
            out << "close ";
            print_obj(exp.args.i_refer.var, out);
            out << ' ';
            out << "vmx:" << exp.args.i_refer.x;
        } break;
        case VmExpKind::Test: {
            out << "test "
                << "vmx:" << exp.args.i_test.next_if_t << ' '
                << "vmx:" << exp.args.i_test.next_if_f;
        } break;
        case VmExpKind::Assign: {
            out << "assign ";
            print_obj(exp.args.i_assign.var, out);
            out << ' ';
            out << "vmx:" << exp.args.i_assign.x;
        } break;
        case VmExpKind::Conti: {
            out << "conti ";
            out << "vmx:" << exp.args.i_conti.x;
        } break;
        case VmExpKind::Nuate: {
            out << "nuate ";
            print_obj(exp.args.i_nuate.var, out);
            out << ' '
                << "vmx:" << exp.args.i_nuate.s;
        } break;
        case VmExpKind::Frame: {
            out << "frame "
                << "vmx:" << exp.args.i_frame.x << ' '
                << "vmx:" << exp.args.i_frame.ret;
        } break;
        case VmExpKind::Argument: {
            out << "argument "
                << "vmx:" << exp.args.i_argument.x;
        } break;
        case VmExpKind::Apply: {
            out << "apply";
        } break;
        case VmExpKind::Return: {
            out << "return";
        } break;
        case VmExpKind::Define: {
            out << "define ";
            print_obj(exp.args.i_define.var, out);
            out << " "
                << "vmx:" << exp.args.i_define.next;
        } break;
    }
    out << ")";
}
void VirtualMachine::dump_all_files(std::ostream& out) {
    for (size_t i = 0; i < m_files.size(); i++) {
        out << "  " "- file #:" << 1+i << std::endl;
        auto f = m_files[i];

        for (size_t j = 0; j < f.line_code_objs.size(); j++) {
            Object* line_code_obj = f.line_code_objs[j];
            VmProgram program = f.line_programs[j];

            out << "    " "  > ";
            print_obj(line_code_obj, out);
            out << std::endl;
            out << "    " " => " << "(vmx:" << program.s << " vmx:" << program.t << ")";
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

void add_file_to_vm(VirtualMachine* vm, std::string const& file_name, std::vector<Object*> objs) {
    // todo: iteratively compile each statement, such that...
    //  - i < len(objs)-1 => 'next' of last statement is first instruction of (i+1)th object
    //  - i = len(objs)-1 => 'next' of last statement is 'halt'
    vm->add_file(file_name, std::move(objs));
}

void sync_execute_vm(VirtualMachine* vm, bool print_each_line) {
    if (print_each_line) {
        vm->sync_execute<true>();
    } else {
        vm->sync_execute<false>();
    }
}

void dump_vm(VirtualMachine* vm, std::ostream& out) {
    vm->dump(out);
}