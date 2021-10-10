#include "vm.hh"

#include <vector>
#include <string>
#include <cstdint>
#include <sstream>
#include <array>

#include <config/config.hh>
#include "feedback.hh"
#include "object.hh"
#include "printing.hh"

//
// VmStack:
//

using VmStackID = size_t;
// ^-- TODO: implement 'stack' of CallFrames
//     TODO: store stacks on the VM: cf `nuate` instruction

//
// VmExp data: each expression either stores a VM instruction or a constant
// All VmExps are are stored in a flat table in the 'VirtualMachine'.
//  - this ensures traversal during interpretation is of similar efficiency to bytecode with padding
//  - TODO: do we need to traverse this structure to perform GC? cf Ch4
//

using VmExpID = size_t;

enum class VmExpKind: VmExpID {
    // Instructions:
    IHalt,
    IRefer,
    IConstant,
    IClose,
    ITest,
    IAssign,
    IConti,
    INuate,
    IFrame,
    IArgument,
    IApply,
    IReturn
};
union VmExpArgs {
    struct {} i_halt;
    struct { Object const* var; VmExpID x; } i_refer;
    struct { Object const* constant; VmExpID x; } i_constant;
    struct { Object const* vars; VmExpID body; VmExpID x; } i_close;
    struct { VmExpID next_if_t; VmExpID next_if_f; } i_test;
    struct { Object const* var; VmExpID x; } i_assign;
    struct { VmExpID x; } i_conti;
    struct { VmStackID s; Object const* var; } i_nuate;
    struct { VmExpID x; VmExpID ret; } i_frame;
    struct { VmExpID x; } i_argument;
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
static_assert(sizeof(VmExp) == 4*sizeof(size_t), "Unexpected sizeof(VmExp)");

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
    VirtualMachine(size_t reserved_file_count = 32);
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
    VmExpID new_vmx_nuate(VmStackID stack_id, Object const* var);
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
    for (VmFile const& file: m_files) {
        for (Object const* o: file.line_code_objs) {
            delete o;
        }
    }
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
    return help_new_vmx(VmExpKind::IHalt).first;
}
VmExpID VirtualMachine::new_vmx_refer(Object const* var, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::IRefer);
    auto& args = exp_ref.args.i_refer;
    args.var = var;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_constant(Object const* constant, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::IConstant);
    auto& args = exp_ref.args.i_constant;
    args.constant = constant;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_close(Object const* vars, VmExpID body, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::IClose);
    auto& args = exp_ref.args.i_close;
    args.vars = vars;
    args.body = body;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_test(VmExpID next_if_acc_t, VmExpID next_if_acc_f) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::ITest);
    auto& args = exp_ref.args.i_test;
    args.next_if_t = next_if_acc_t;
    args.next_if_f = next_if_acc_f;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_assign(Object const* var, VmExpID next) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::IAssign);
    auto& args = exp_ref.args.i_assign;
    args.var = var;
    args.x = next;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_conti(VmExpID x) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::IConti);
    auto& args = exp_ref.args.i_conti;
    args.x = x;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_nuate(VmStackID stack_id, Object const* var) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::INuate);
    auto& args = exp_ref.args.i_nuate;
    args.s = stack_id;
    args.var = var;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_frame(VmExpID x, VmExpID ret) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::IFrame);
    auto& args = exp_ref.args.i_frame;
    args.x = x;
    args.ret = ret;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_argument(VmExpID x) {
    auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::IArgument);
    auto& args = exp_ref.args.i_argument;
    args.x = x;
    return exp_id;
}
VmExpID VirtualMachine::new_vmx_apply() {
    return help_new_vmx(VmExpKind::IApply).first;
}
VmExpID VirtualMachine::new_vmx_return() {
    return help_new_vmx(VmExpKind::IReturn).first;
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
        };
        case ObjectKind::Pair: {
            return translate_code_obj__pair_list(static_cast<PairObject const*>(obj), next);
        };
        default: {
            return new_vmx_constant(obj, next);
        }
    }
}
VmExpID VirtualMachine::translate_code_obj__pair_list(PairObject const* obj, VmExpID next) {
    Object const* raw_head = obj->car();
#if !CONFIG_OPTIMIZED_MODE
    if (raw_head->kind() != ObjectKind::Symbol) {
        std::stringstream ss;
        ss << "Expected a symbol key-word as the first element of a pair-list";
        error(ss.str());
        throw SsiError();
    }
#endif
    auto head = static_cast<SymbolObject const*>(raw_head);
    auto args = obj->cdr();
    auto keyword_symbol_id = head->name();

    // todo: implement me: match the `record-case` on p. 56 of `three-imp.pdf`
    
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
    }
    else {
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
    return m_exps[vmx_id].kind == VmExpKind::IReturn;
}

// todo: implement printing for VM instructions
// todo: implement execution for VM instructions
// todo: implement a debugger for the VM?
//   - some sort of line associations so our back-trace is meaningful

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

