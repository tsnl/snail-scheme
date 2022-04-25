#include "ss-jit/vm.hh"

#include <vector>
#include <string>
#include <sstream>
#include <array>
#include <iostream>
#include <iomanip>
#include <cstdint>
#include <cmath>
#include <cassert>

#include "ss-config/config.hh"
#include "ss-core/feedback.hh"
#include "ss-core/object.hh"
#include "ss-jit/printing.hh"
#include "ss-core/common.hh"
#include "ss-jit/std.hh"
#include "ss-jit/vcode.hh"
#include "ss-jit/vthread.hh"
#include "ss-jit/compiler.hh"

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
    public:
        explicit VirtualMachine(Gc* gc, size_t reserved_file_count, VirtualMachineStandardProcedureBinder binder);
        ~VirtualMachine();
    
    // Source code loading + compilation:
    public:
        void program(VCode&& code);

    // Blocking execution functions:
    // Run each expression in each file sequentially on this thread.
    public:
        template <bool print_each_line>
        void sync_execute();

    // Interpreter environment setup:
    public:
        OBJECT closure(VmExpID body, my_ssize_t vars_count, my_ssize_t s);
        my_ssize_t find_link(my_ssize_t n, my_ssize_t e);
        my_ssize_t find_link(my_ssize_t n, OBJECT e);
        OBJECT continuation(my_ssize_t s);
    public:
        OBJECT save_stack(my_ssize_t s);
        my_ssize_t restore_stack(OBJECT vector);
        my_ssize_t push(OBJECT v, my_ssize_t s) { return m_thread.stack().push(v, s); }
        my_ssize_t push(my_ssize_t v, my_ssize_t s) { return push(OBJECT::make_integer(v), s); }
        OBJECT index(my_ssize_t s, my_ssize_t i) { return m_thread.stack().index(s, i); }
        OBJECT index(OBJECT s, my_ssize_t i) { return index(s.as_signed_fixnum(), i); }
        void index_set(my_ssize_t s, my_ssize_t i, OBJECT v) { m_thread.stack().index_set(s, i, v); }
    public:
        VmExpID closure_body(OBJECT c);
        OBJECT index_closure(OBJECT c, my_ssize_t n);

    // Properties:
    public:
        GcThreadFrontEnd& gc_tfe() { return *m_thread.gc_tfe(); }
        Compiler& jit_compiler() { return m_jit_compiler; }
        VCode& code() { return m_jit_compiler.code(); }
    };

    //
    // ctor/dtor
    //

    VirtualMachine::VirtualMachine(
        Gc* gc,
        size_t file_count, 
        VirtualMachineStandardProcedureBinder binder
    ):  m_thread(gc),
        m_jit_compiler(*m_thread.gc_tfe())
    {
        // setting up threads using initial val-rib:
        m_thread.init();
    }

    VirtualMachine::~VirtualMachine() {
        // todo: clean up code object memory-- leaking for now.
        //  - cannot delete `BoolObject` or other singletons
        // for (VScript const& file: m_rom.files()) {
        //     for (OBJECT o: file.line_code_objs) {
        //         delete o;
        //     }
        // }
    }

    //
    // Source code loading + compilation (p. 57 of 'three-imp.pdf')
    //

    void VirtualMachine::program(VCode&& new_code) {
        code().flash(std::move(new_code));
    }

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

        // for each line object in each file...
        for (VScript& f: code().files()) {
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
                    std::wcout << L"\tVM <- (" << m_thread.regs().x << ") ";
                    print_one_exp(m_thread.regs().x, std::cout);
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
                        case VmExpKind::Constant: {
                            m_thread.regs().a = exp.args.i_constant.obj;
                            m_thread.regs().x = exp.args.i_constant.x;
                        } break;
                        case VmExpKind::Close: {
                            m_thread.regs().a = closure(exp.args.i_close.body, exp.args.i_close.vars_count, m_thread.regs().s);
                            m_thread.regs().x = exp.args.i_close.x;
                            m_thread.regs().s -= exp.args.i_close.vars_count;
                        } break;
                        case VmExpKind::Test: {
                            if (m_thread.regs().a.is_boolean(false)) {
                                m_thread.regs().x = exp.args.i_test.next_if_f;
                            } else {
                                m_thread.regs().x = exp.args.i_test.next_if_t;
                            }
                        } break;
                        // case VmExpKind::Assign: {
                        //     auto rem_value_rib = lookup(exp.args.i_assign.var, m_thread.regs().e);
                        //     set_car(rem_value_rib, m_thread.regs().a);
                        //     m_thread.regs().x = exp.args.i_assign.x;
                        // } break;
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
                            m_thread.regs().x = exp.args.i_frame.ret;
                            m_thread.regs().s = 
                                push(OBJECT::make_integer(exp.args.i_frame.x), 
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
                            }
                            else if (m_thread.regs().a.is_ext_callable()) {
                                // a C++ function is called; no 'return' required since stack returns after function call
                                // by C++ rules.
                                auto a = static_cast<EXT_CallableObject*>(m_thread.regs().a.as_ptr());
                                // leave env unaffected, since after evaluation, we continue with original env
                                
                                // popping the stack frame added by 'Frame':
                                // NOTE: this part is usually handled by VmExpKind::Return
                                
                                // TODO: retrieve arguments as stack pointer, provide as arguments
                                // - builtin functions will not work until this is fixed!
                                // - since arguments are pushed last to first, can index (0, 1, 2, ...)
                                //   to access arguments.
                                //   This translates to s-1, s-2, ...
                                // - HOWEVER, variadic arguments?

                                // auto num_args = a->arg_count();
                                // auto s = m_thread.regs().s - num_args;
                                // // m_thread.regs().a = a->cb()(m_thread.regs().r);
                                // m_thread.regs().x = index(s, 0).as_signed_fixnum();
                                // m_thread.regs().f = index(s, 1).as_signed_fixnum();
                                // m_thread.regs().c = index(s, 2);
                                // m_thread.regs().s = s - 3;

                                error("NotImplemented: EXT_CallableObject");
                                throw SsiError();
                            }
                            else {
                                std::stringstream ss;
                                ss << "apply: expected a procedure, received: ";
                                print_obj(m_thread.regs().a, ss);
                                ss << std::endl;
                                error(ss.str());
                                throw SsiError();
                            }
                        } break;
                        case VmExpKind::Return: {
                            auto s = m_thread.regs().s - exp.args.i_return.n;
                            m_thread.regs().x = index(s, 0).as_signed_fixnum();
                            m_thread.regs().f = index(s, 1).as_signed_fixnum();
                            m_thread.regs().c = index(s, 2);
                            m_thread.regs().s = s - 3;
                        } break;
                        // case VmExpKind::Define: {
                        //     m_thread.regs().x = exp.args.i_define.next;
                        //     m_thread.regs().e = extend(m_thread.regs().e, list(m_thread.gc_tfe(), OBJECT::make_boolean(false)));
                        //     // DEBUG:
                        //     // {
                        //     //     auto def_name = exp.args.i_define.var.as_interned_symbol();
                        //     //     std::cout << "define: " << interned_string(def_name) << ": " m_thread.regs().a << std::endl;
                        //     //     std::cout << "  - now, env is: " << m_thread.regs().e << std::endl;
                        //     // }
                        // } break;
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
        }
    }

    OBJECT VirtualMachine::closure(VmExpID body, my_ssize_t n, my_ssize_t s) {
        std::vector<OBJECT> items;
        items.resize(1 + n);
        items[0] = OBJECT::make_integer(body);
        for (my_ssize_t i = 0; i < n; i++) {
            items[1+i] = index(s, i);
        }
        auto mem = gc_tfe().allocate_bytes((1 + n) * sizeof(OBJECT));
        return OBJECT::make_generic_boxed(new(mem) VectorObject(std::move(items)));
    }

    my_ssize_t VirtualMachine::find_link(my_ssize_t n, my_ssize_t e) {
        return (n == 0) ? e : find_link(n - 1, index(e, -1));
    }
    my_ssize_t VirtualMachine::find_link(my_ssize_t n, OBJECT e) {
        return find_link(n, e.as_signed_fixnum());
    }

    OBJECT VirtualMachine::continuation(my_ssize_t s) {
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
    OBJECT VirtualMachine::save_stack(my_ssize_t s) {
        std::vector<OBJECT> vs{m_thread.stack().begin(), m_thread.stack().begin() + s};
        return OBJECT::make_generic_boxed(new VectorObject(std::move(vs)));
    }
    my_ssize_t VirtualMachine::restore_stack(OBJECT vector) {
        assert(vector.is_vector() && "Expected stack to restore to be a 'vector' object");
        std::vector<OBJECT>& cpp_vector = dynamic_cast<VectorObject*>(vector.as_ptr())->as_cpp_vec();
        assert(cpp_vector.size() <= m_thread.stack().capacity() && "Cannot restore a stack larger than VM stack's capacity.");
        std::copy(cpp_vector.begin(), cpp_vector.end(), m_thread.stack().begin());
        return cpp_vector.size();
    }

    VmExpID VirtualMachine::closure_body(OBJECT c) {
        return static_cast<VectorObject*>(c.as_ptr())->operator[](0).as_signed_fixnum();
    }
    OBJECT VirtualMachine::index_closure(OBJECT c, my_ssize_t n) {
        return static_cast<VectorObject*>(c.as_ptr())->operator[](1 + n);
    }

    //
    //
    // Interface:
    //
    //

    VirtualMachine* create_vm(
        Gc* gc,
        VirtualMachineStandardProcedureBinder binder,
        int reserved_file_count
    ) {
        auto vm = new VirtualMachine(gc, reserved_file_count, binder); 
        return vm;
    }
    void destroy_vm(VirtualMachine* vm) {
        delete vm;
    }
    void program_vm(VirtualMachine* vm, VCode&& code) {
        vm->program(std::move(code));
    }
    GcThreadFrontEnd* vm_gc_tfe(VirtualMachine* vm) {
        return &vm->gc_tfe();
    }
    void sync_execute_vm(VirtualMachine* vm, bool print_each_line) {
        if (print_each_line) {
            vm->sync_execute<true>();
        } else {
            vm->sync_execute<false>();
        }
    }
    void dump_vm(VirtualMachine* vm, std::ostream& out) {
        std::cerr << "<dump>" << std::endl;
        std::cerr << "=== VROM ===" << std::endl;
        vm->code().dump(out);
        std::cerr << "</dump>" << std::endl;
    }

}   // namespace ss
