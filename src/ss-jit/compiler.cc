#include "ss-jit/compiler.hh"

#include <utility>
#include "ss-jit/printing.hh"
#include "ss-core/object.hh"

namespace ss {

    Compiler::Compiler(GcThreadFrontEnd& gc_tfe) 
    :   m_code(),
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
        // TODO: add 'globals' table
    {}
     
    std::pair<size_t, size_t> Compiler::compile_lookup(OBJECT symbol, OBJECT var_env) {
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
                    return {rib_index, elt_index};
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

    VScript Compiler::compile_script(std::string str, std::vector<OBJECT> line_code_objects) {
        std::vector<VmProgram> line_programs;
        line_programs.reserve(line_code_objects.size());
        for (auto const code_object: line_code_objects) {
            auto program = compile_line(code_object, OBJECT::make_null());
            line_programs.push_back(program);
        }
        return VScript{std::move(line_code_objects), std::move(line_programs)};
    }
    VmProgram Compiler::compile_line(OBJECT line_code_obj, OBJECT var_e) {
        VmExpID last_exp_id = m_code.new_vmx_halt();
        VmExpID res = compile_exp(line_code_obj, last_exp_id, var_e);
        return {res, last_exp_id};
    }
    VmExpID Compiler::compile_exp(OBJECT obj, VmExpID next, OBJECT var_e) {
        // iteratively translating this line to a VmProgram
        //  - cf p. 87 of 'three-imp.pdf', §4.3.2: Translation and Evaluation
        switch (obj_kind(obj)) {
            case GranularObjectType::InternedSymbol: {
                auto [n, m] = compile_lookup(obj, var_e);
                return m_code.new_vmx_refer(n, m, next);
            }
            case GranularObjectType::Pair: {
                return compile_pair_list_exp(static_cast<PairObject*>(obj.as_ptr()), next, var_e);
            }
            default: {
                return m_code.new_vmx_constant(obj, next);
            }
        }
    }
    VmExpID Compiler::compile_pair_list_exp(PairObject* obj, VmExpID next, OBJECT var_e) {
        // corresponds to 'record-case'

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
                return m_code.new_vmx_constant(quoted, next);
            }
            else if (keyword_symbol_id == m_builtin_intstr_id_cache.lambda) {
                // lambda
                auto args_array = extract_args<2>(args);
                auto vars = args_array[0];
                auto body = args_array[1];
                
                check_vars_list_else_throw(vars);

                return m_code.new_vmx_close(
                    vars,
                    compile_exp(
                        body,
                        m_code.new_vmx_return(1 + list_length(vars)),
                        compile_extend(var_e, vars)
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
                return compile_exp(
                    cond_code_obj,
                    m_code.new_vmx_test(
                        compile_exp(then_code_obj, next, var_e),
                        compile_exp(else_code_obj, next, var_e)
                    ),
                    var_e
                );
            }
            // else if (keyword_symbol_id == m_builtin_intstr_id_cache.set) {
            //     // set!
            //     auto args_array = extract_args<2>(args);
            //     auto var_obj = args_array[0];
            //     auto set_obj = args_array[1];   // we set the variable to this object, 'set' in past-tense
            //     assert(var_obj.is_interned_symbol());
            //     return compile_exp(
            //         set_obj,
            //         m_code.new_vmx_assign(compile_lookup(var_obj, var_e), next),
            //         var_e
            //     );
            // }
            else if (keyword_symbol_id == m_builtin_intstr_id_cache.call_cc) {
                // call/cc
                // NOTE: procedure type check occurs in 'apply' later

                auto args_array = extract_args<1>(args);
                auto x = args_array[0];
                
                return m_code.new_vmx_frame(
                    next, 
                    m_code.new_vmx_conti(
                        m_code.new_vmx_argument(
                            compile_exp(x, m_code.new_vmx_apply(), var_e)
                        )
                    )
                );
            } 
            // else if (keyword_symbol_id == m_builtin_intstr_id_cache.define) {
            //     // define
            //     auto args_array = extract_args<2>(args);
            //     auto structural_signature = args_array[0];
            //     auto body = args_array[1];
            //     auto name = OBJECT::make_null();
            //     auto pattern_ok = false;

            //     if (structural_signature.is_interned_symbol()) {
            //         // (define <var> <initializer>)
            //         pattern_ok = true;
            //         name = structural_signature;
            //     }
            //     else if (structural_signature.is_pair()) {
            //         // (define (<fn-name> <arg-vars...>) <initializer>)
            //         // desugars to 
            //         // (define <fn-name> (lambda (<arg-vars) <initializer>))
            //         pattern_ok = true;

            //         auto fn_name = car(structural_signature);
            //         auto arg_vars = cdr(structural_signature);
                    
            //         check_vars_list_else_throw(arg_vars);

            //         if (!fn_name.is_interned_symbol()) {
            //             std::stringstream ss;
            //             ss << "define: invalid function name: ";
            //             print_obj(fn_name, ss);
            //             error(ss.str());
            //             throw SsiError();
            //         }

            //         name = fn_name;
            //         body = list(&m_gc_tfe, OBJECT::make_interned_symbol(intern("lambda")), arg_vars, body);
            //     }

            //     // de-sugared handler:
            //     // NOTE: when computing ref instances:
            //     // - 'Define' instruction runs before 'Assign'
            //     if (pattern_ok) {
            //         OBJECT vars = list(&m_gc_tfe, name);
            //         OBJECT new_env = compile_extend(var_e, vars);
            //         auto [n, m] = compile_lookup(name, new_env);
            //         ScopedVmExp body_res = compile_exp(
            //             body,
            //             m_code.new_vmx_assign(n, m, next),
            //             new_env
            //         );
            //         return ScopedVmExp {
            //             m_code.new_vmx_define(name, body_res),
            //             body_res.new_var_env
            //         };
            //     } else {
            //         error("Invalid args to 'define'");
            //         throw SsiError();
            //     }
            // }
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

                // compiling arguments from last to first, linking:
                VmExpID final_begin_instruction = next;
                while (!obj_stack.empty()) {
                    final_begin_instruction = compile_exp(obj_stack.back(), final_begin_instruction, var_e);
                    obj_stack.pop_back();
                }

                // returning:
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
            OBJECT rem_args = args;
            VmExpID next_c = compile_exp(head, m_code.new_vmx_apply(), var_e);
            for (;;) {
                if (rem_args.is_null()) {
                    return m_code.new_vmx_frame(next, next_c);
                } else {
                    next_c = compile_exp(
                        car(rem_args),
                        m_code.new_vmx_argument(next_c),
                        var_e
                    );
                    rem_args = cdr(rem_args);
                }
            }
        }

        // unreachable
    }
    bool Compiler::is_tail_vmx(VmExpID vmx_id) {
        return m_code[vmx_id].kind == VmExpKind::Return;
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