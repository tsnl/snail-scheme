#include "vm.hh"

#include <vector>
#include <string>
#include <cstdint>
#include <sstream>

#include <config/config.hh>
#include "feedback.hh"
#include "object.hh"

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
    struct { VmExpID obj; VmExpID x; } i_constant;
    struct { Object const* vars; Object const* body; VmExpID x; } i_close;
    struct { VmExpID then; VmExpID else_; } i_test;
    struct { Object const* var; VmExpID x; } i_assign;
    struct { VmExpID x; } i_conti;
    struct { VmExpID s; VmExpID var; } i_nuate;
    struct { VmExpID x; VmExpID ret; } i_frame;
    struct { VmExpID x; } i_argument;
    struct {} i_apply;
    struct {} i_return_;
};
struct VmExp {
    VmExpKind kind;
    VmExpArgs args;
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
    VmExpID new_vmx_close(Object const* vars, Object const* body, VmExpID next);
    VmExpID new_vmx_test(VmExpID next_if_acc_t, VmExpID next_if_acc_f);
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
        .set = intern("set"),
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

// todo: implement me

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
    Object* raw_head = obj->car();
#if CONFIG_DEBUG_MODE
    if (raw_head->kind() != ObjectKind::Symbol) {
        std::stringstream ss;
        ss << "Expected a symbol key-word as the first element of a pair-list";
        error(ss.str());
        throw SsiError();
    }
#endif
    auto head = static_cast<SymbolObject*>(raw_head);
    auto tail = obj->cdr();
    auto keyword_symbol_id = head->name();

    // todo: implement me: match the `record-case` on p. 56 of `three-imp.pdf`
    //  - can write a template-based argument extractor to obtain args as an array, post errors.

    if (keyword_symbol_id == m_builtin_intstr_id_cache.quote) {
        if (!tail) {
            // todo: error
        }
        return new_vmx_constant(tail, next);
    }
    if (keyword_symbol_id == m_builtin_intstr_id_cache.lambda) {
        // todo: check args
        // return new_vmx_close()
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

