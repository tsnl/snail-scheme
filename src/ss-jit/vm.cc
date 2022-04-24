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
#include "ss-jit/vrom.hh"
#include "ss-jit/vthread.hh"

namespace ss {

    //
    // VmSyntheticEnv
    // A way to build vars and vals in parallel.
    //

    struct VmSyntheticEnv {
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
        VRom m_rom;
        VThread m_thread;
        
        OBJECT m_init_var_rib;
        OBJECT m_init_val_rib;
        bool m_init_env_locked;

    public:
        explicit VirtualMachine(Gc* gc, size_t reserved_file_count, VirtualMachineStandardProcedureBinder binder);
        ~VirtualMachine();
    
    // Source code loading + compilation:
    public:
        void program(VRom&& rom);

    // Blocking execution functions:
    // Run each expression in each file sequentially on this thread.
    public:
        template <bool print_each_line>
        void sync_execute();

    // Interpreter environment setup:
    public:
        void define_builtin_value(std::string name_str, OBJECT elt_obj);
        void define_builtin_fn(std::string name_str, EXT_CallableCb callback, std::vector<std::string> arg_names);
        static OBJECT closure(VmExpID body, OBJECT env);
        static OBJECT lookup(OBJECT symbol, OBJECT env_raw);
        OBJECT continuation(my_ssize_t s);
    public:
        OBJECT extend(OBJECT e, OBJECT vals);
    public:
        OBJECT save_stack(my_ssize_t s);
        my_ssize_t restore_stack(OBJECT vector);
        my_ssize_t push(OBJECT v, my_ssize_t s) { return m_thread.stack().push(v, s); }
        OBJECT index(my_ssize_t s, my_ssize_t i) { return m_thread.stack().index(s, i); }
        void index_set(my_ssize_t s, my_ssize_t i, OBJECT v) { m_thread.stack().index_set(s, i, v); }

    // Properties:
    public:
        GcThreadFrontEnd& gc_tfe() { return *m_thread.gc_tfe(); }
        VRom const& rom() const { return m_rom; }
        OBJECT default_init_var_rib() const { return m_init_var_rib; }
        OBJECT default_init_val_rib() const { return m_init_val_rib; }
    };

    //
    // ctor/dtor
    //

    VirtualMachine::VirtualMachine(
        Gc* gc,
        size_t file_count, 
        VirtualMachineStandardProcedureBinder binder
    ):  m_thread(gc),
        m_rom(file_count),
        m_init_var_rib(OBJECT::make_null()),
        m_init_val_rib(OBJECT::make_null()),
        m_init_env_locked(false)
    {
        // setting up, then locking the initial environment:
        binder(this);
        m_init_env_locked = true;

        // setting up threads using initial val-rib:
        m_thread.init(m_init_val_rib);
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

    void VirtualMachine::program(VRom&& rom) {
        m_rom.flash(std::move(rom));
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
        for (VScript& f: m_rom.files()) {
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
                    VmExp const& exp = m_rom[m_thread.regs().x];

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
                        case VmExpKind::Refer: {
                            m_thread.regs().a = car(lookup(exp.args.i_refer.var, m_thread.regs().e));
                            m_thread.regs().x = exp.args.i_refer.x;
                        } break;
                        case VmExpKind::Constant: {
                            m_thread.regs().a = exp.args.i_constant.constant;
                            m_thread.regs().x = exp.args.i_constant.x;
                        } break;
                        case VmExpKind::Close: {
                            m_thread.regs().a = closure(exp.args.i_close.body, m_thread.regs().e);
                            m_thread.regs().x = exp.args.i_close.x;
                        } break;
                        case VmExpKind::Test: {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                            if (!m_thread.regs().a.is_boolean()) {
                                std::stringstream ss;
                                ss << "test: expected a `bool` expression in a conditional, received: ";
                                print_obj(m_thread.regs().a, ss);
                                error(ss.str());
                                throw SsiError();
                            }
    #endif
                            if (m_thread.regs().a.is_boolean(true)) {
                                m_thread.regs().x = exp.args.i_test.next_if_t;
                            } else {
                                m_thread.regs().x = exp.args.i_test.next_if_f;
                            }
                        } break;
                        case VmExpKind::Assign: {
                            auto rem_value_rib = lookup(exp.args.i_assign.var, m_thread.regs().e);
                            set_car(rem_value_rib, m_thread.regs().a);
                            m_thread.regs().x = exp.args.i_assign.x;
                        } break;
                        case VmExpKind::Conti: {
                            m_thread.regs().a = continuation(m_thread.regs().s);
                            m_thread.regs().x = exp.args.i_conti.x;
                        } break;
                        case VmExpKind::Nuate: {
                            m_thread.regs().a = car(lookup(exp.args.i_nuate.var, m_thread.regs().e));
                            m_thread.regs().x = m_rom.new_vmx_return();
                            m_thread.regs().s = restore_stack(exp.args.i_nuate.s);
                        } break;
                        case VmExpKind::Frame: {
                            auto encoded_ret = OBJECT::make_integer(exp.args.i_frame.x);
                            m_thread.regs().x = exp.args.i_frame.ret;
                            m_thread.regs().s = push(encoded_ret, push(m_thread.regs().e, push(m_thread.regs().r, m_thread.regs().s)));
                            m_thread.regs().r = OBJECT::make_null();
                        } break;
                        case VmExpKind::Argument: {
                            m_thread.regs().x = exp.args.i_argument.x;
                            m_thread.regs().r = cons(m_thread.gc_tfe(), m_thread.regs().a, m_thread.regs().r);
                        } break;
                        case VmExpKind::Apply: {
    #if !CONFIG_DISABLE_RUNTIME_TYPE_CHECKS
                            if (!is_procedure(m_thread.regs().a)) {
                                std::stringstream ss;
                                ss << "apply: expected a procedure, received: ";
                                print_obj(m_thread.regs().a, ss);
                                ss << std::endl;
                                error(ss.str());
                                throw SsiError();
                            }
    #endif
                            if (m_thread.regs().a.is_closure()) {
                                // a Scheme function is called
                                auto a = static_cast<VMA_ClosureObject*>(m_thread.regs().a.as_ptr());
                                OBJECT new_e;
                                try {
                                    new_e = extend(a->e(), m_thread.regs().r);
                                } catch (SsiError const&) {
                                    std::stringstream ss;
                                    ss << "See applied procedure: " << m_thread.regs().a;
                                    more(ss.str());
                                    throw;
                                }

                                // DEBUG:
                                // std::cerr 
                                //     << "Applying: " << m_thread.regs().a << std::endl
                                //     << "- args: " << m_thread.regs().r << std::endl
                                //     << "- next: " << m_thread.regs().x << std::endl;

                                // m_thread.regs().a = m_thread.regs().a;
                                m_thread.regs().x = a->body();
                                m_thread.regs().e = new_e;
                                m_thread.regs().r = OBJECT::make_null();
                            }
                            else if (m_thread.regs().a.is_ext_callable()) {
                                // a C++ function is called; no 'return' required since stack returns after function call
                                // by C++ rules.
                                auto a = static_cast<EXT_CallableObject*>(m_thread.regs().a.as_ptr());
    //                          // leave env unaffected, since after evaluation, we continue with original env
                                
                                // popping the stack frame added by 'Frame':
                                // NOTE: this part is usually handled by VmExpKind::Return
                                m_thread.regs().a = a->cb()(m_thread.regs().r);
                                m_thread.regs().x = index(m_thread.regs().s, 0).as_signed_fixnum();
                                m_thread.regs().e = index(m_thread.regs().s, 1);
                                m_thread.regs().r = index(m_thread.regs().s, 2);
                                m_thread.regs().s = m_thread.regs().s - 3;
                            }
                            else {
                                error("Invalid callable while type-checks disabled");
                                throw SsiError();
                            }
                        } break;
                        case VmExpKind::Return: {
                            auto s = m_thread.regs().s;
                            // std::cerr << "RETURN!" << std::endl;
                            // m_thread.regs().a = m_thread.regs().a;
                            m_thread.regs().x = index(s, 0).as_signed_fixnum();
                            m_thread.regs().e = index(s, 1);
                            m_thread.regs().r = index(s, 2);
                            m_thread.regs().s = m_thread.regs().s - 3;
                        } break;
                        case VmExpKind::Define: {
                            m_thread.regs().x = exp.args.i_define.next;
                            m_thread.regs().e = extend(m_thread.regs().e, list(m_thread.gc_tfe(), OBJECT::make_boolean(false)));
                            // DEBUG:
                            // {
                            //     auto def_name = exp.args.i_define.var.as_interned_symbol();
                            //     std::cout << "define: " << interned_string(def_name) << ": " m_thread.regs().a << std::endl;
                            //     std::cout << "  - now, env is: " << m_thread.regs().e << std::endl;
                            // }
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
                    print_obj(m_thread.regs().a, std::cout);
                    std::cout << std::endl;
                }
            }
        }
    }

    void VirtualMachine::define_builtin_value(std::string name_str, OBJECT elt_obj) {
        OBJECT var_obj = OBJECT::make_interned_symbol(intern(std::move(name_str)));
        m_init_var_rib = cons(m_thread.gc_tfe(), var_obj, m_init_var_rib);
        m_init_val_rib = cons(m_thread.gc_tfe(), elt_obj, m_init_val_rib);
    }

    void VirtualMachine::define_builtin_fn(
        std::string name_str, 
        EXT_CallableCb callback, 
        std::vector<std::string> arg_names
    ) {
        // constructing a 'closure' object:
        OBJECT vars_list = OBJECT::make_null();
        for (size_t i = 0; i < arg_names.size(); i++) {
            vars_list = cons(m_thread.gc_tfe(), OBJECT::make_interned_symbol(intern(arg_names[i])), vars_list);
        }
        auto elt_obj_raw = new EXT_CallableObject(callback, m_init_val_rib, vars_list);
        auto elt_obj = OBJECT::make_generic_boxed(elt_obj_raw);

        // binding:
        define_builtin_value(std::move(name_str), elt_obj);
    }

    OBJECT VirtualMachine::closure(VmExpID body, OBJECT env) {
        return OBJECT{new VMA_ClosureObject(body, env)};
    }

    OBJECT VirtualMachine::lookup(OBJECT symbol, OBJECT env) {
        assert(env.is_list() && "broken 'env' in lookup");

        if (env.is_null()) {
            error("broken env");
            throw SsiError();
        }
        if (!(symbol.is_pair() && car(symbol).is_integer() && cdr(symbol).is_integer())) {
            std::stringstream ss;
            ss << "broken refer pair: expected (rib . elt), got: " << symbol << std::endl;
            error(ss.str());
            throw SsiError();
        }

        my_ssize_t rib_index = car(symbol).as_signed_fixnum();
        my_ssize_t elt_index = cdr(symbol).as_signed_fixnum();
        
        // std::cerr << "LOOKUP: (" << rib_index << " . " << elt_index << ")" << std::endl;
        // std::cerr << "\tENV: " << env << std::endl;

        OBJECT rem_ribs = env;
        while (rib_index > 0) {
            rib_index--;
            rem_ribs = cdr(rem_ribs);
        }
        OBJECT chosen_rib = car(rem_ribs);
        assert(rib_index == 0);

        OBJECT rem_elts = chosen_rib;
        for (my_ssize_t i = 0; i < elt_index; i++) {
            assert(rem_elts.is_pair() && "invalid ref pair");
            rem_elts = cdr(rem_elts);
        }
        return rem_elts;
    }

    OBJECT VirtualMachine::continuation(my_ssize_t s) {
        auto closest_var_ref = cons(m_thread.gc_tfe(), OBJECT::make_integer(0), OBJECT::make_integer(0));
        return closure(
            m_rom.new_vmx_nuate(save_stack(s), closest_var_ref), 
            OBJECT::make_null()
        );
    }

    OBJECT VirtualMachine::extend(OBJECT e, OBJECT vals) {
        return cons(m_thread.gc_tfe(), vals, e);
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
    void program_vm(VirtualMachine* vm, VRom&& rom) {
        vm->program(std::move(rom));
    }
    GcThreadFrontEnd* vm_gc_tfe(VirtualMachine* vm) {
        return &vm->gc_tfe();
    }
    OBJECT vm_default_init_var_rib(VirtualMachine* vm) {
        return vm->default_init_var_rib();
    }
    void define_builtin_value_in_vm(VirtualMachine* vm, std::string name_str, OBJECT object) {
        vm->define_builtin_value(std::move(name_str), object);
    }
    void define_builtin_procedure_in_vm(VirtualMachine* vm, std::string name_str,  EXT_CallableCb callback, std::vector<std::string> arg_names) {
        vm->define_builtin_fn(std::move(name_str), callback, std::move(arg_names));
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
        vm->rom().dump(out);
        std::cerr << "</dump>" << std::endl;
    }

}   // namespace ss
