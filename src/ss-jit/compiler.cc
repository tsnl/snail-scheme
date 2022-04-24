#include "ss-jit/compiler.hh"
#include "ss-jit/printing.hh"
#include "ss-core/object.hh"

namespace ss {

    Compiler::Compiler(GcThreadFrontEnd& gc_tfe) 
    :   m_rom(),
        m_gc_tfe(gc_tfe),
        m_builtin_intstr_id_cache({
            .quote = intern("quote"),
            .lambda = intern("lambda"),
            .if_ = intern("if"),
            .set = intern("set!"),
            .call_cc = intern("call/cc"),
            .define = intern("define"),
            .begin = intern("begin")
        })
    {}
     
    OBJECT Compiler::compile_lookup(OBJECT symbol, OBJECT var_env) {
        // compile-time type-checks
        {
            bool ok = (
                (var_env.is_list() && "broken 'env' in compile_lookup") &&
                (symbol.is_interned_symbol() && "broken 'symbol' in compile_lookup")
            );
            if (!ok) {
                throw SsiError();
            }
        }

        // DEBUG:
        // {
        //     std::cerr 
        //         << "COMPILE_LOOKUP:" << std::endl
        //         << "\t" << symbol << std::endl
        //         << "\t" << var_env << std::endl;
        // }

        IntStr sym_name = symbol.as_interned_symbol();

        // iterating through ribs in the environment:
        // the environment is a 'list of pairs of lists'
        //  - each pair of lists is called a rib-pair or 'ribs'
        //  - each list in the pair is a named rib-- either the value rib or named rib
        size_t rib_index = 0;
        for (
            OBJECT rem_ribs = var_env;
            rem_ribs.is_pair();
            rem_ribs = cdr(rem_ribs)
        ) {
            auto variable_rib = car(rem_ribs);
            assert(
                (variable_rib.is_pair() || variable_rib.is_null())
                && "broken compile-time env"
            );

            size_t elt_index = 0;
            for (
                OBJECT rem_variable_rib = variable_rib;
                !rem_variable_rib.is_null();
                rem_variable_rib = cdr(rem_variable_rib)
            ) {
                assert(!rem_variable_rib.is_null() && "Expected rem_variable_rib to be non-null with rem_value_rib");
                assert(car(rem_variable_rib).is_interned_symbol() && "Expected a symbol in variable rib");
                auto variable_rib_head_name = car(rem_variable_rib).as_interned_symbol();
                if (variable_rib_head_name == sym_name) {
                    // return the remaining value rib so we can reuse for 'set'
                    return cons(&m_gc_tfe, OBJECT::make_integer(rib_index), OBJECT::make_integer(elt_index));
                } else {
                    elt_index++;
                }
            }

            rib_index++;
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

    VScript Compiler::compile_script(std::string str, std::vector<OBJECT> line_code_objects, OBJECT init_var_rib) {
        std::vector<VmProgram> line_programs;
        line_programs.reserve(line_code_objects.size());
        ScopedVmProgram scoped_program;
        scoped_program.new_var_env = list(&m_gc_tfe, init_var_rib);
        for (auto const code_object: line_code_objects) {
            scoped_program = translate_single_line_code_obj(code_object, scoped_program.new_var_env);
            line_programs.push_back(scoped_program.program_code);
        }
        return VScript{std::move(line_code_objects), std::move(line_programs)};
    }
    ScopedVmProgram Compiler::translate_single_line_code_obj(OBJECT line_code_obj, OBJECT var_e) {
        VmExpID last_exp_id = m_rom.new_vmx_halt();
        ScopedVmExp res = translate_code_obj(line_code_obj, last_exp_id, var_e);
        return ScopedVmProgram { 
            VmProgram {res.exp_id, last_exp_id}, 
            res.new_var_env
        };
    }
    ScopedVmExp Compiler::translate_code_obj(OBJECT obj, VmExpID next, OBJECT var_e) {
        // iteratively translating this line to a VmProgram
        //  - cf p. 56 of 'three-imp.pdf', §3.4.2: Translation
        switch (obj_kind(obj)) {
            case GranularObjectType::InternedSymbol: {
                return ScopedVmExp{m_rom.new_vmx_refer(compile_lookup(obj, var_e), next), var_e};
            }
            case GranularObjectType::Pair: {
                return translate_code_obj__pair_list(static_cast<PairObject*>(obj.as_ptr()), next, var_e);
            }
            default: {
                return ScopedVmExp{m_rom.new_vmx_constant(obj, next), var_e};
            }
        }
    }
    ScopedVmExp Compiler::translate_code_obj__pair_list(PairObject* obj, VmExpID next, OBJECT var_e) {
        // retrieving key properties:
        OBJECT head = obj->car();
        OBJECT args = obj->cdr();

        // first, trying to handle a builtin function invocation:
        if (head.is_interned_symbol()) {
            // keyword first argument => may be builtin
            auto keyword_symbol_id = head.as_interned_symbol();

            if (keyword_symbol_id == m_builtin_intstr_id_cache.quote) {
                // quote
                auto quoted = extract_args<1>(args)[0];
                return ScopedVmExp { m_rom.new_vmx_constant(quoted, next), var_e };
            }
            else if (keyword_symbol_id == m_builtin_intstr_id_cache.lambda) {
                // lambda
                auto args_array = extract_args<2>(args);
                auto vars = args_array[0];
                auto body = args_array[1];
                
                check_vars_list_else_throw(vars);

                return ScopedVmExp {
                    m_rom.new_vmx_close(
                        vars,
                        translate_code_obj(
                            body,
                            m_rom.new_vmx_return(),
                            compile_extend(var_e, vars)
                        ).exp_id,
                        next
                    ),
                    var_e
                };
            }
            else if (keyword_symbol_id == m_builtin_intstr_id_cache.if_) {
                // if
                auto args_array = extract_args<3>(args);
                auto cond_code_obj = args_array[0];
                auto then_code_obj = args_array[1];
                auto else_code_obj = args_array[2];
                return translate_code_obj(
                    cond_code_obj,
                    m_rom.new_vmx_test(
                        translate_code_obj(then_code_obj, next, var_e).exp_id,
                        translate_code_obj(else_code_obj, next, var_e).exp_id
                    ),
                    var_e
                );
            }
            else if (keyword_symbol_id == m_builtin_intstr_id_cache.set) {
                // set!
                auto args_array = extract_args<2>(args);
                auto var_obj = args_array[0];
                auto set_obj = args_array[1];   // we set the variable to this object, 'set' in past-tense
                assert(var_obj.is_interned_symbol());
                return translate_code_obj(
                    set_obj,
                    m_rom.new_vmx_assign(compile_lookup(var_obj, var_e), next),
                    var_e
                );
            }
            else if (keyword_symbol_id == m_builtin_intstr_id_cache.call_cc) {
                // call/cc
                auto args_array = extract_args<1>(args);
                auto x = args_array[0];
                // todo: check that 'x', the called function, is in fact a procedure.
                auto c = m_rom.new_vmx_conti(
                    m_rom.new_vmx_argument(
                        translate_code_obj(x, m_rom.new_vmx_apply(), var_e).exp_id
                    )
                );
                return ScopedVmExp {
                    ((is_tail_vmx(next)) ? c : m_rom.new_vmx_frame(next, c)),
                    var_e
                };
            } 
            else if (keyword_symbol_id == m_builtin_intstr_id_cache.define) {
                // define
                auto args_array = extract_args<2>(args);
                auto structural_signature = args_array[0];
                auto body = args_array[1];
                auto name = OBJECT::make_null();
                auto pattern_ok = false;

                if (structural_signature.is_interned_symbol()) {
                    // (define <var> <initializer>)
                    pattern_ok = true;
                    name = structural_signature;
                }
                else if (structural_signature.is_pair()) {
                    // (define (<fn-name> <arg-vars...>) <initializer>)
                    // desugars to 
                    // (define <fn-name> (lambda (<arg-vars) <initializer>))
                    pattern_ok = true;

                    auto fn_name = car(structural_signature);
                    auto arg_vars = cdr(structural_signature);
                    
                    check_vars_list_else_throw(arg_vars);

                    if (!fn_name.is_interned_symbol()) {
                        std::stringstream ss;
                        ss << "define: invalid function name: ";
                        print_obj(fn_name, ss);
                        error(ss.str());
                        throw SsiError();
                    }

                    name = fn_name;
                    body = list(&m_gc_tfe, OBJECT::make_interned_symbol(intern("lambda")), arg_vars, body);
                }

                // de-sugared handler:
                // NOTE: when computing ref instances:
                // - 'Define' instruction runs before 'Assign'
                if (pattern_ok) {
                    OBJECT vars = list(&m_gc_tfe, name);
                    OBJECT new_env = compile_extend(var_e, vars);
                    ScopedVmExp body_res = translate_code_obj(
                        body,
                        m_rom.new_vmx_assign(compile_lookup(name, new_env), next),
                        new_env
                    );
                    return ScopedVmExp {
                        m_rom.new_vmx_define(name, body_res.exp_id),
                        body_res.new_var_env
                    };
                } else {
                    error("Invalid args to 'define'");
                    throw SsiError();
                }
            }
            else if (keyword_symbol_id == m_builtin_intstr_id_cache.begin) {
                // (begin expr ...+)

                // ensuring at least one argument is provided:
                if (args.is_null()) {
                    error("begin: expected at least one expression form to evaluate, got 0.");
                    throw SsiError();
                }

                // assembling each code object on a stack to translate in reverse order:
                std::vector<OBJECT> obj_stack;
                obj_stack.reserve(32);
                OBJECT rem_args = args;
                while (!rem_args.is_null()) {
                    obj_stack.push_back(car(rem_args));
                    rem_args = cdr(rem_args);
                }

                // translating:
                VmExpID final_begin_instruction = next;
                while (!obj_stack.empty()) {
                    final_begin_instruction = translate_code_obj(obj_stack.back(), final_begin_instruction, var_e).exp_id;
                    obj_stack.pop_back();
                }

                return ScopedVmExp {final_begin_instruction, var_e};
            }
            else {
                // continue to the branch below...
            }
        }

        // otherwise, handling a function call:
        //  NOTE: the 'car' expression could be a non-symbol, e.g. a lambda expression for an IIFE
        {
            // function call
            ScopedVmExp c = translate_code_obj(head, m_rom.new_vmx_apply(), var_e);
            OBJECT c_args = args;
            while (!c_args.is_null()) {
                c = translate_code_obj(
                    car(c_args),
                    m_rom.new_vmx_argument(c.exp_id),
                    c.new_var_env
                );
                c_args = cdr(c_args);
            }
            if (is_tail_vmx(next)) {
                return c;
            } else {
                return ScopedVmExp {
                    m_rom.new_vmx_frame(next, c.exp_id),
                    c.new_var_env
                };
            }
        }
    }
    bool Compiler::is_tail_vmx(VmExpID vmx_id) {
        return m_rom[vmx_id].kind == VmExpKind::Return;
    }
    void Compiler::check_vars_list_else_throw(OBJECT vars) {
        OBJECT rem_vars = vars;
        while (!rem_vars.is_null()) {
            OBJECT head = car(rem_vars);
            rem_vars = cdr(rem_vars);

            if (!head.is_interned_symbol()) {
                std::stringstream ss;
                ss << "Invalid variable list for lambda: expected symbol, got: ";
                print_obj(head, ss);
                ss << std::endl;
                error(ss.str());
                throw SsiError();
            }
        }
    }
    OBJECT Compiler::compile_extend(OBJECT e, OBJECT vars) {
        auto res = cons(&m_gc_tfe, vars, e);
        // std::cerr 
        //     << "COMPILE_EXTEND:" << std::endl
        //     << "\tbefore: " << e << std::endl
        //     << "\tafter:  " << res << std::endl;
        return res;
    }

}