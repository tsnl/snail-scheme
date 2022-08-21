#include "ss-core/vm.hh"

#include <vector>
#include <string>
#include <sstream>
#include <array>
#include <iostream>
#include <iomanip>
#include <cstdint>
#include <cmath>
#include <cassert>

#include "ss-core/config.hh"
#include "ss-core/feedback.hh"
#include "ss-core/object.hh"
#include "ss-core/printing.hh"
#include "ss-core/common.hh"
#include "ss-core/std.hh"
#include "ss-core/vcode.hh"
#include "ss-core/vthread.hh"
#include "ss-core/compiler.hh"

namespace ss {

    //
    // VmSyntheticEnv
    // A way to build vars and vals in parallel.
    //

    struct VEnv {
        OBJECT var_ribs;
        OBJECT val_ribs;
    };

    //
    // VirtualMachine (VM)
    //  - stores and constructs VmExps
    //  - runs VmExps to `halt`
    //  - de-allocates all expressions (and thus, all `Object` instances parsed and possibly reused)
    //

    class VirtualMachine {
    private:
        VThread m_thread;
        Compiler m_jit_compiler;
        std::vector<OBJECT> m_global_vals;
    public:
        explicit VirtualMachine(Gc* gc, VirtualMachineStandardProcedureBinder binder);
        ~VirtualMachine();
    
    // Source code loading + compilation:
    public:
        void program(VCode&& code);

    // Blocking execution functions:
    // Run each expression in each file sequentially on this thread.
    public:
        template <bool print_each_line>
        OBJECT sync_execute();

        template <bool print_each_line>
        OBJECT sync_execute_subr(VSubr const& subr);

    // Interpreter environment setup:
    public:
        OBJECT closure(VmExpID body, ssize_t vars_count, ssize_t s);
        ssize_t find_link(ssize_t n, ssize_t e);
        ssize_t find_link(ssize_t n, OBJECT e);
        OBJECT continuation(ssize_t s);
    public:
        OBJECT save_stack(ssize_t s);
        ssize_t restore_stack(OBJECT vector);
        ssize_t push(OBJECT v, ssize_t s) { return m_thread.stack().push(v, s); }
        ssize_t push(ssize_t v, ssize_t s) { return push(OBJECT::make_integer(v), s); }
        OBJECT index(ssize_t s, ssize_t i) { return m_thread.stack().index(s, i); }
        OBJECT index(OBJECT s, ssize_t i) { return index(s.as_integer(), i); }
        void index_set(ssize_t s, ssize_t i, OBJECT v) { m_thread.stack().index_set(s, i, v); }
    public:
        VmExpID closure_body(OBJECT c);
        OBJECT index_closure(OBJECT c, ssize_t n);
    public: // for tail-call optimizations, three-imp 4.6.2 p.111
        ssize_t shift_args(ssize_t n, ssize_t m, ssize_t s);

    // Properties:
    public:
        GcThreadFrontEnd& gc_tfe() { return *m_thread.gc_tfe(); }
        Compiler& jit_compiler() { return m_jit_compiler; }
        VCode& code() { return *m_jit_compiler.code(); }
    };

    //
    // ctor/dtor
    //

    VirtualMachine::VirtualMachine(
        Gc* gc,
        VirtualMachineStandardProcedureBinder binder
    ):  m_thread(gc),
        m_jit_compiler(*m_thread.gc_tfe())
    {
        // setting up threads using initial val-rib:
        m_thread.init();

        // binding platform globals:
        binder(this);
    }

    VirtualMachine::~VirtualMachine() {}

    //
    // Blocking execution:
    //

    template <bool print_each_line>
    OBJECT VirtualMachine::sync_execute() {
        // this function is a direct translation of the function `VM` on p. 60 of `three-imp.pdf`, except
        //  - the tail-recursive function is transformed into a loop
        //  - rather than considering any return value, we just execute the script and rely on IO and 
        //    side-effects to provide feedback to the user. Thus, 'halt' is ignored.
        //  - each line object results in a `halt` instruction--
        //      - if `print_each_line` is true, we print the input and output lines to stdout
        //      - NOTE: `print_each_line` is a compile-time-constant-- if false, branches should be optimized out.

        // initializing globals to 'undef':
        m_global_vals.clear();
        m_global_vals.resize(m_jit_compiler.count_globals(), OBJECT::undef);
        m_jit_compiler.initialize_platform_globals(m_global_vals);

        // for each line object in each file...
        for (VSubr const& f: code().subrs()) {
            sync_execute_subr<print_each_line>(f);
        }
        assert(m_thread.regs().s == 0);
        assert(m_thread.regs().f == 0);
        return m_thread.regs().a;
    }
    template <bool print_each_line>
    OBJECT VirtualMachine::sync_execute_subr(VSubr const& f) {
        auto line_count = f.line_code_objs.size();
        for (size_t i = 0; i < line_count; i++) {
            // acquiring input:
            OBJECT input = f.line_code_objs[i];
            VmProgram program = f.line_programs[i];

            // setting start instruction:
            m_thread.regs().x = program.s;

            // running iteratively until 'halt':
            //  - cf `VM` function on p. 60 of `three-imp.pdf`
            bool vm_is_running = true;
            while (vm_is_running) {
                VmExp const& exp = code()[m_thread.regs().x];

                // DEBUG ONLY: print each instruction on execution to help trace
                // todo: perhaps include a thread-ID? Some synchronization around IO [basically GIL]
#if CONFIG_PRINT_EACH_INSTRUCTION_ON_EXECUTION
                std::cout << "\tVM <- (" << m_thread.regs().x << ") ";
                code().print_one_exp(m_thread.regs().x, std::cout);
                std::cout << std::endl;
#endif

                switch (exp.kind) {
                    case VmExpKind::Halt: {
                        // m_thread.regs().a now contains the return value of this computation.
                        vm_is_running = false;
                    } break;
                    case VmExpKind::ReferLocal: {
                        m_thread.regs().a = index(m_thread.regs().f, exp.args.i_refer.n);
                        m_thread.regs().x = exp.args.i_refer.x;
                    } break;
                    case VmExpKind::ReferFree: {
                        m_thread.regs().a = index_closure(m_thread.regs().c, exp.args.i_refer.n);
                        m_thread.regs().x = exp.args.i_refer.x;
                    } break;
                    case VmExpKind::ReferGlobal: {
                        m_thread.regs().a = m_global_vals[exp.args.i_refer.n];
                        m_thread.regs().x = exp.args.i_refer.x;
                    } break;
                    case VmExpKind::Indirect: {
                        m_thread.regs().a = unbox(m_thread.regs().a);
                        m_thread.regs().x = exp.args.i_indirect.x;
                    } break;
                    case VmExpKind::Constant: {
                        m_thread.regs().a = exp.args.i_constant.obj;
                        m_thread.regs().x = exp.args.i_constant.x;
                    } break;
                    case VmExpKind::Close: {
                        // instantiate a closure with bound free-var arguments,
                        // then pop these args as though a constructor were applied.
                        m_thread.regs().a = closure(exp.args.i_close.body, exp.args.i_close.vars_count, m_thread.regs().s);
                        m_thread.regs().x = exp.args.i_close.x;
                        m_thread.regs().s -= exp.args.i_close.vars_count;
                    } break;
                    case VmExpKind::Box: {
                        // replaces nth argument with a box of its former contents
                        // see three-imp p.105
                        auto s = m_thread.regs().s;
                        auto n = exp.args.i_box.n;
                        index_set(s, n, box(&gc_tfe(), index(s, n)));
                        m_thread.regs().x = exp.args.i_box.x;
                    } break;
                    case VmExpKind::Test: {
                        if (m_thread.regs().a.is_boolean(false)) {
                            m_thread.regs().x = exp.args.i_test.next_if_f;
                        } else {
                            m_thread.regs().x = exp.args.i_test.next_if_t;
                        }
                    } break;
                    case VmExpKind::AssignLocal: {
                        // see three-imp p.106
                        auto f = m_thread.regs().f;
                        auto n = exp.args.i_assign.n;
                        set_box(index(f, n), m_thread.regs().a);
                        m_thread.regs().x = exp.args.i_assign.x;
                    } break;
                    case VmExpKind::AssignFree: {
                        auto c = m_thread.regs().c;
                        auto n = exp.args.i_assign.n;
                        set_box(index_closure(c, n), m_thread.regs().a);
                        m_thread.regs().x = exp.args.i_assign.x;
                    } break;
                    case VmExpKind::AssignGlobal: {
                        m_global_vals[exp.args.i_refer.n] = m_thread.regs().a;
                        m_thread.regs().x = exp.args.i_refer.x;
                    } break;
                    case VmExpKind::Conti: {
                        m_thread.regs().a = continuation(m_thread.regs().s);
                        m_thread.regs().x = exp.args.i_conti.x;
                    } break;
                    case VmExpKind::Nuate: {
                        m_thread.regs().x = exp.args.i_nuate.x;
                        m_thread.regs().s = restore_stack(exp.args.i_nuate.stack);
                    } break;
                    case VmExpKind::Frame: {
                        // pushing...
                        // first (c, f, ret) last
                        m_thread.regs().x = exp.args.i_frame.fn_body_x;
                        m_thread.regs().s = 
                            push(OBJECT::make_integer(exp.args.i_frame.post_ret_x), 
                                push(m_thread.regs().f, 
                                    push(m_thread.regs().c, m_thread.regs().s)));
                    } break;
                    case VmExpKind::Argument: {
                        m_thread.regs().x = exp.args.i_argument.x;
                        m_thread.regs().s = push(m_thread.regs().a, m_thread.regs().s);
                    } break;
                    case VmExpKind::Apply: {
                        if (m_thread.regs().a.is_closure()) {
                            // a Scheme function is called: actually a vector
                            OBJECT c = m_thread.regs().a;
#if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                            assert(c.is_vector());
#endif
                            // DEBUG:
                            // std::cerr 
                            //     << "Applying: " << m_thread.regs().a << std::endl
                            //     << "- args: " << m_thread.regs().r << std::endl
                            //     << "- next: " << m_thread.regs().x << std::endl;

                            // m_thread.regs().a = m_thread.regs().a;
                            m_thread.regs().x = closure_body(c);
                            m_thread.regs().f = m_thread.regs().s;
                            m_thread.regs().c = c;
                            // m_thread.regs().s = m_thread.regs().s;
                        } else {
                            std::stringstream ss;
                            ss << "apply: expected a procedure, received: " << m_thread.regs().a;
                            error(ss.str());
                            throw SsiError();
                        }
                    } break;
                    case VmExpKind::Return: {
                        auto s = m_thread.regs().s - exp.args.i_return.n;
                        m_thread.regs().x = index(s, 0).as_integer();
                        m_thread.regs().f = index(s, 1).as_integer();
                        m_thread.regs().c = index(s, 2);
                        m_thread.regs().s = s - 3;
                    } break;
                    case VmExpKind::Shift: {
                        // three-imp p.112
                        auto m = exp.args.i_shift.m;
                        auto n = exp.args.i_shift.n;
                        auto x = exp.args.i_shift.x;
                        auto s = m_thread.regs().s;
                        m_thread.regs().x = x;
                        m_thread.regs().s = shift_args(n, m, s);
                    } break;
                    case VmExpKind::PInvoke: {
                        // WARNING: 
                        // args are pushed without a wrapping Frame for this.
                        // This elides a 'Frame' and 'Return' instruction pair.

                        auto n = exp.args.i_pinvoke.n;
                        auto x = exp.args.i_pinvoke.x;
                        auto p = exp.args.i_pinvoke.proc_id;
                        
                        ArgView args{m_thread.stack(), m_thread.regs().s, n};
                        auto res = m_jit_compiler.code()->platform_proc_cb(p)(args);
                        
                        m_thread.regs().a = res;    // store retval in accum reg
                        m_thread.regs().x = x;      // prep for next statement
                        m_thread.regs().s -= n;     // pop arguments
                    } break;
                    default: {
                        std::stringstream ss;
                        ss << "NotImplemented: running interpreter for instruction VmExpKind::?";
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
                print_obj(m_thread.regs().a, std::cout);
                std::cout << std::endl;
            }
        }
        return m_thread.regs().a;
    }

    OBJECT VirtualMachine::closure(VmExpID body, ssize_t n, ssize_t s) {
        std::vector<OBJECT> items;
        items.resize(1 + n);
        items[0] = OBJECT::make_integer(body);
        for (ssize_t i = 0; i < n; i++) {
            items[1+i] = index(s, i);
        }
        return OBJECT::make_ptr(new(&gc_tfe(), VectorObject::sci) VectorObject(std::move(items)));
    }

    ssize_t VirtualMachine::find_link(ssize_t n, ssize_t e) {
        return (n == 0) ? e : find_link(n - 1, index(e, -1));
    }
    ssize_t VirtualMachine::find_link(ssize_t n, OBJECT e) {
        return find_link(n, e.as_integer());
    }

    OBJECT VirtualMachine::continuation(ssize_t s) {
        // cf p.86 of three-imp
        return closure(
            code().new_vmx_refer_local(
                0,
                code().new_vmx_nuate(save_stack(s), code().new_vmx_return(0))
            ),
            0,
            s   // -> FIXME: guess, check if this is right, could be a source of bugs
        );
        throw SsiError();
    }
    OBJECT VirtualMachine::save_stack(ssize_t s) {
        std::vector<OBJECT> vs{m_thread.stack().begin(), m_thread.stack().begin() + s};
        return OBJECT::make_ptr(new(&gc_tfe(), VectorObject::sci) VectorObject(std::move(vs)));
    }
    ssize_t VirtualMachine::restore_stack(OBJECT vector) {
        assert(vector.is_vector() && "Expected stack to restore to be a 'vector' object");
        std::vector<OBJECT>& cpp_vector = dynamic_cast<VectorObject*>(vector.as_ptr())->as_cpp_vec();
        assert(cpp_vector.size() <= m_thread.stack().capacity() && "Cannot restore a stack larger than VM stack's capacity.");
        std::copy(cpp_vector.begin(), cpp_vector.end(), m_thread.stack().begin());
        return cpp_vector.size();
    }

    VmExpID VirtualMachine::closure_body(OBJECT c) {
        return c.as_vector_p()->operator[](0).as_integer();
    }
    OBJECT VirtualMachine::index_closure(OBJECT c, ssize_t n) {
        return c.as_vector_p()->operator[](1 + n);
    }

    ssize_t VirtualMachine::shift_args(ssize_t n, ssize_t m, ssize_t s) {
        // see three-imp p.111
        ssize_t i = n - 1;
        while (i >= 0) {
            index_set(s, i + m, index(s, i));
            --i;
        }
        return s - m;
    }

    //
    //
    // Interface:
    //
    //

    VirtualMachine* create_vm(
        Gc* gc,
        VirtualMachineStandardProcedureBinder binder
    ) {
        auto vm = new VirtualMachine(gc, binder); 
        return vm;
    }
    void destroy_vm(VirtualMachine* vm) {
        delete vm;
    }
    GcThreadFrontEnd* vm_gc_tfe(VirtualMachine* vm) {
        return &vm->gc_tfe();
    }
    OBJECT sync_execute_vm(VirtualMachine* vm, bool print_each_line) {
        if (print_each_line) {
            return vm->sync_execute<true>();
        } else {
            return vm->sync_execute<false>();
        }
    }
    void dump_vm(VirtualMachine* vm, std::ostream& out) {
        std::cerr << "<dump>" << std::endl;
        std::cerr << "=== VROM ===" << std::endl;
        vm->code().dump(out);
        std::cerr << "</dump>" << std::endl;
    }
    Compiler* vm_compiler(VirtualMachine* vm) {
        return &vm->jit_compiler();
    }

    OBJECT vm_interp_expr(VirtualMachine* vm, OBJECT line_code_obj) {
        VSubr subr = vm->jit_compiler().compile_expr("subr-1shot", line_code_obj);
        return vm->sync_execute_subr<false>(subr);
    }
    OBJECT vm_interp_subr(VirtualMachine* vm, std::vector<OBJECT> line_code_objs, bool print_each_line) {
        VSubr subr = vm->jit_compiler().compile_subr("subr", line_code_objs);
        if (print_each_line) {
            return vm->sync_execute_subr<true>(subr);
        } else {
            return vm->sync_execute_subr<false>(subr);
        }
    }

    //
    // Utility
    //

    void vm_bind_platform_procedure(
        VirtualMachine* vm, 
        std::string proc_name,
        PlatformProcCb callable_cb,
        std::vector<std::string> arg_names,
        std::string docstring_more,
        bool is_variadic
    ) {
        std::stringstream docstring;
        docstring
            << "(" << proc_name << " ";
            for (size_t i = 0; i < arg_names.size(); i++) {
                docstring << arg_names[i];
                if (i+1 < arg_names.size()) {
                    docstring << " ";
                }
            }
        docstring
            << ")";
        if (!docstring_more.empty()) {
            docstring << ": " << docstring_more;
        }

        Compiler* c = vm_compiler(vm);
        c->define_platform_proc(
            intern(std::move(proc_name)),
            std::move(arg_names),
            callable_cb,
            docstring.str(),
            is_variadic
        );
    }


}   // namespace ss
