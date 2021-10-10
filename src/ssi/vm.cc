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
#include "vm-exp.hh"

//
// VmStack:
//

// todo: 

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
    std::vector<Object const*> line_code_objs;
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
    std::vector<VmExp> m_exps;
    std::vector< VmFile > m_files;

    const struct {
        IntStr const quote;
        IntStr const lambda;
        IntStr const if_;
        IntStr const set;
        IntStr const call_cc;
    } m_builtin_intstr_id_cache;
  public:
    explicit VirtualMachine(size_t reserved_file_count = 32);
    ~VirtualMachine();
  
  // creating VM expressions:
  private:
    std::pair<VmExpID, VmExp&> help_new_vmx(VmExpKind kind);
    VmExpID new_vmx_halt();
    VmExpID new_vmx_refer(Object const* var, VmExpID next);
    VmExpID new_vmx_constant(Object const* constant, VmExpID next);
    VmExpID new_vmx_close(Object const* vars, VmExpID body, VmExpID next);
    VmExpID new_vmx_test(VmExpID next_if_t, VmExpID next_if_f);
    VmExpID new_vmx_assign(Object const* var, VmExpID next);
    VmExpID new_vmx_conti(VmExpID x);
    VmExpID new_vmx_nuate(VmStackPtr stack_id, Object const* var);
    VmExpID new_vmx_frame(VmExpID x, VmExpID ret);
    VmExpID new_vmx_argument(VmExpID x);
    VmExpID new_vmx_apply();
    VmExpID new_vmx_return();

  // TODO: creating VM stacks
  private:
    
  // Source code loading + compilation:
  public:
    // add_file eats an std::vector<Object*> containing each line
    void add_file(std::string const& file_name, std::vector<Object const*> objs);
  private:
    VmProgram translate_single_line_code_obj(Object const* line_code_obj);
    VmExpID translate_code_obj(Object const* obj, VmExpID next);
    VmExpID translate_code_obj__pair_list(PairObject const* obj, VmExpID next);
    bool is_tail_vmx(VmExpID vmx_id);

  // Blocking execution functions:
  // Run each expression in each file sequentially on this thread.
  public:
    template <bool print_each_line>
    void sync_execute();

  // Interpreter environment setup:
  public:
    static Object const* mk_default_root_env();
    static Object const* closure(Object const* body, Object const* e, Object const* args);

  // Debug dumps:
  public:
    void dump(std::ostream& out);
    void dump_all_exps(std::ostream& out);
    void dump_all_files(std::ostream& out);
};

//
// ctor/dtor
//

VirtualMachine::VirtualMachine(size_t file_count) 
:   m_exps(),
    m_files(),
    m_builtin_intstr_id_cache({
        .quote = intern("quote"),
        .lambda = intern("lambda"),
        .if_ = intern("if"),
        .set = intern("set!"),
        .call_cc = intern("call/cc")
    })
{
    m_exps.reserve(4096);
    m_files.reserve(file_count);
}

VirtualMachine::~VirtualMachine() {
    // todo: clean up code object memory-- leaking for now.
    //  - cannot delete `BoolObject` or other singletons
    // for (VmFile const& file: m_files) {
    //     for (Object const* o: file.line_code_objs) {
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
VmExpID VirtualMachine::new_vmx_refer(Object const* var, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Refer);
    auto& args = exp_ref.args.i_refer;
    args.var = var;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_constant(Object const* constant, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Constant);
    auto& args = exp_ref.args.i_constant;
    args.constant = constant;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_close(Object const* vars, VmExpID body, VmExpID next) {
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
VmExpID VirtualMachine::new_vmx_assign(Object const* var, VmExpID next) {
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
VmExpID VirtualMachine::new_vmx_nuate(VmStackPtr stack_id, Object const* var) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Nuate);
    auto& args = exp_ref.args.i_nuate;
    args.s = stack_id;
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

//
// Creating VM stacks
//

// todo: implement me

//
// Source code loading + compilation (p. 57 of 'three-imp.pdf')
//

void VirtualMachine::add_file(std::string const& file_name, std::vector<Object const*> objs) {
    if (!objs.empty()) {
        // translating each line into a program that terminates with 'halt'
        std::vector<VmProgram> line_programs;
        line_programs.reserve(objs.size());
        for (Object const* line_code_obj: objs) {
            VmProgram program = translate_single_line_code_obj(line_code_obj);
            line_programs.push_back(program);
        }

        // storing the input lines and the programs on this VM:
        VmFile new_file = {std::move(objs), line_programs};
        m_files.push_back(new_file);
    } else {
        warning(std::string("VM: Input file `") + file_name + "` is empty.");
    }
}

VmProgram VirtualMachine::translate_single_line_code_obj(Object const* line_code_obj) {
    VmExpID last_exp_id = new_vmx_halt();
    VmExpID first_exp_id = translate_code_obj(line_code_obj, last_exp_id);
    return VmProgram {first_exp_id, last_exp_id};
}
VmExpID VirtualMachine::translate_code_obj(Object const* obj, VmExpID next) {
    // todo: iteratively translate this line to a VmProgram
    //  - cf p. 56 of 'three-imp.pdf', §3.4.2: Translation
    auto obj_kind = obj->kind();
    switch (obj_kind) {
        case ObjectKind::Symbol: {
            return new_vmx_refer(obj, next);
        }
        case ObjectKind::Pair: {
            return translate_code_obj__pair_list(static_cast<PairObject const*>(obj), next);
        }
        default: {
            return new_vmx_constant(obj, next);
        }
    }
}
VmExpID VirtualMachine::translate_code_obj__pair_list(PairObject const* obj, VmExpID next) {
    // retrieving key properties:
    Object const* head = obj->car();
    Object const* args = obj->cdr();

    // first, trying to handle a builtin function invocation:
    if (head->kind() == ObjectKind::Symbol) {
        // keyword first argument
        auto sym_head = static_cast<SymbolObject const*>(head);
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
        } else {
            // continue to the branch below...
        }
    }

    // otherwise, handling a function call:
    {
        // function call
        VmExpID call_c = translate_code_obj(
            head, 
            new_vmx_apply()
        );
        Object const* call_args = args;
        while (call_args) {
            call_c = translate_code_obj(
                car(call_args),
                new_vmx_argument(call_c)
            );
            call_args = cdr(call_args);
        }
        if (is_tail_vmx(next)) {
            return call_c;
        } else {
            return new_vmx_frame(next, call_c);
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

    // register decl+init:
    Object const* a;        // the accumulator
    VmExpID x;              // the next expression
    Object const* e;        // the current environment
    Object const* r;        // value rib; used to compute arguments for 'apply'
    VmStackPtr s;            // the current stack

    e = mk_default_root_env();

    // for each line object in each file...
    for (auto f: m_files) {
        auto line_count = f.line_code_objs.size();
        for (size_t i = 0; i < line_count; i++) {
            // acquiring input:
            Object const* input = f.line_code_objs[i];
            VmProgram program = f.line_programs[i];

            // setting start instruction:
            x = program.s;

            // running iteratively until 'halt':
            //  - cf `VM` function on p. 60 of `three-imp.pdf`
            bool vm_is_running = true;
            while (vm_is_running) {
                VmExp const& exp = m_exps[x];
                switch (exp.kind) {
                    case VmExpKind::Halt: {
                        vm_is_running = false;
                    } break;
                    case VmExpKind::Refer: {
                        // todo: implement the 'lookup' function-- may need to be destructive
                        x = exp.args.i_refer.x;
                    } break;
                    case VmExpKind::Constant: {
                        a = exp.args.i_constant.constant;
                        x = exp.args.i_constant.x;
                    } break;
                    case VmExpKind::Close: {
                        a = closure(
                            exp.args.i_close.body,
                            e,
                            exp.args.i_close.vars
                        );
                    } break;
                    default: {
                        std::stringstream ss;
                        ss << "NotImplemented: VmExpKind::?";
                        error(ss.str());
                        throw SsiError();
                    }
                }
            }

            // printing if desired:
            if (print_each_line) {
                std::cout << "  > ";
                print_obj(input, std::cout);
                std::cout << std::endl;
                std::cout << " => ";
                print_obj(input, std::cout);
                std::cout << std::endl;
            }
        }
    }
}

VmEnv* VirtualMachine::mk_default_root_env() {
    auto env = nullptr;

    // todo: define builtins, e.g. car/cdr, is___?, etc.
    //  - each 'rib' is a pair of 'elements' and 'variables' lists

    return env;
}

//
// VM dumps:
//

void VirtualMachine::dump(std::ostream& out) {
    out << "[Expression Table]" << std::endl;
    dump_all_exps(out);
    
    out << "[File Table]" << std::endl;
    dump_all_files(out);
}
void VirtualMachine::dump_all_exps(std::ostream& out) {
    size_t pad_w = static_cast<size_t>(std::ceil(std::log(1+m_exps.size()) / std::log(10)));
    for (size_t index = 0; index < m_exps.size(); index++) {
        out << "  [";
        out << std::setfill('0') << std::setw(pad_w) << index;
        out << "] ";

        out << "(";
        auto exp = m_exps[index];
        switch (exp.kind) {
            case VmExpKind::Halt: {
                out << "halt";
            } break;
            case VmExpKind::Refer: {
                out << "refer ";
                print_obj(exp.args.i_refer.var, out);
                out << ' ';
                out << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_refer.x;
            } break;
            case VmExpKind::Constant: {
                out << "constant ";
                print_obj(exp.args.i_constant.constant, out);
                out << ' ';
                out << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_constant.x;
            } break;
            case VmExpKind::Close: {
                out << "close ";
                print_obj(exp.args.i_refer.var, out);
                out << ' ';
                out << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_refer.x;
            } break;
            case VmExpKind::Test: {
                out << "test "
                    << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_test.next_if_t << ' '
                    << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_test.next_if_f;
            } break;
            case VmExpKind::Assign: {
                out << "assign ";
                print_obj(exp.args.i_assign.var, out);
                out << ' ';
                out << "vmx:" << exp.args.i_assign.x;
            } break;
            case VmExpKind::Conti: {
                out << "conti ";
                out << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_conti.x;
            } break;
            case VmExpKind::Nuate: {
                out << "nuate ";
                print_obj(exp.args.i_nuate.var, out);
                out << ' '
                    << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_nuate.s;
            } break;
            case VmExpKind::Frame: {
                out << "frame "
                    << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_frame.x << ' '
                    << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_frame.ret;
            } break;
            case VmExpKind::Argument: {
                out << "argument "
                    << "vmx:" << std::setfill('0') << std::setw(pad_w) << exp.args.i_argument.x;
            } break;
            case VmExpKind::Apply: {
                out << "apply";
            } break;
            case VmExpKind::Return: {
                out << "return";
            } break;
        }
        out << ")" << std::endl;
    }
}
void VirtualMachine::dump_all_files(std::ostream& out) {
    for (size_t i = 0; i < m_files.size(); i++) {
        out << "  " "- file #:" << 1+i << std::endl;
        auto f = m_files[i];

        for (size_t j = 0; j < f.line_code_objs.size(); j++) {
            Object const* line_code_obj = f.line_code_objs[j];
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

void add_file_to_vm(VirtualMachine* vm, std::string const& file_name, std::vector<Object const*> objs) {
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