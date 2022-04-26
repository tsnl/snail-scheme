#include "ss-jit/compiler.hh"

#include <utility>
#include "ss-jit/printing.hh"
#include "ss-core/common.hh"
#include "ss-core/object.hh"
#include "ss-core/feedback.hh"

namespace ss {

    Compiler::Compiler(GcThreadFrontEnd& gc_tfe) 
    :   Analyst(),
        m_code(),
        m_gc_tfe(gc_tfe)
        // TODO: add 'globals' table
    {}
     
    // returns [n, m] = [rib_index, elt_index]
    std::pair<RelVarScope, size_t> Compiler::compile_lookup(OBJECT symbol, OBJECT var_env) {
        // compile-time type-checks
        bool ok = (
            (var_env.is_list() && "broken 'env' in compile_lookup") &&
            (symbol.is_interned_symbol() && "broken 'symbol' in compile_lookup")
        );
        if (!ok) {
            throw SsiError();
        }

        // DEBUG:
        // {
        //     std::cerr 
        //         << "COMPILE_LOOKUP:" << std::endl
        //         << "\t" << symbol << std::endl
        //         << "\t" << var_env << std::endl;
        // }
        
        // checking 'locals'
        {
            OBJECT const all_locals = car(var_env);
            OBJECT locals = all_locals;
            size_t n = 0;
            for (;;) {
                if (locals.is_null()) {
                    break;
                }
                if (ss::is_eq(&m_gc_tfe, car(locals), symbol)) {
                    return {RelVarScope::Local, n};
                }
                // preparing for the next iteration:
                locals = cdr(locals);
                ++n;
            }
        }

        // checking 'free'
        {
            OBJECT const all_free_vars = cdr(var_env);
            OBJECT free = all_free_vars;
            size_t n = 0;
            for (;;) {
                if (free.is_null()) {
                    break;
                }
                if (ss::is_eq(&m_gc_tfe, car(free), symbol)) {
                    return {RelVarScope::Free, n};
                }
                // preparing for the next iteration:
                free = cdr(free);
                ++n;
            }
        }

        // TODO: check globals
        
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
        OBJECT const default_env = ss::cons(&m_gc_tfe, OBJECT::make_null(), OBJECT::make_null());
        line_programs.reserve(line_code_objects.size());
        for (auto const code_object: line_code_objects) {
            auto program = compile_line(code_object, default_env);
            line_programs.push_back(program);
        }
        return VScript{std::move(line_code_objects), std::move(line_programs)};
    }
    VmProgram Compiler::compile_line(OBJECT line_code_obj, OBJECT var_e) {
        OBJECT s = OBJECT::make_null();     // empty set
        VmExpID last_exp_id = m_code.new_vmx_halt();
        VmExpID res = compile_exp(line_code_obj, last_exp_id, var_e, s);
        return {res, last_exp_id};
    }
    VmExpID Compiler::compile_exp(OBJECT x, VmExpID next, OBJECT e, OBJECT s) {
        // iteratively translating this line to a VmProgram
        //  - cf p. 87 of 'three-imp.pdf', §4.3.2: Translation and Evaluation
        switch (obj_kind(x)) {
            case GranularObjectType::InternedSymbol: {
                return compile_refer(
                    x, e, 
                    (is_set_member(x, s) ? m_code.new_vmx_indirect(next) : next)
                );
            }
            case GranularObjectType::Pair: {
                return compile_pair_list_exp(static_cast<PairObject*>(x.as_ptr()), next, e, s);
            }
            default: {
                return m_code.new_vmx_constant(x, next);
            }
        }
    }
    VmExpID Compiler::compile_pair_list_exp(PairObject* obj, VmExpID next, OBJECT e, OBJECT s) {
        // corresponds to 'record-case'

        // retrieving key properties:
        OBJECT head = obj->car();
        OBJECT tail = obj->cdr();

        // first, trying to handle a builtin function invocation:
        if (head.is_interned_symbol()) {
            // keyword first argument => may be builtin
            auto keyword_symbol_id = head.as_interned_symbol();

            if (keyword_symbol_id == m_id_cache.quote) {
                // quote
                auto quoted = extract_args<1>(tail)[0];
                return m_code.new_vmx_constant(quoted, next);
            }
            else if (keyword_symbol_id == m_id_cache.lambda) {
                // lambda
                auto args = extract_args<2>(tail);
                auto vars = args[0];
                auto body = args[1];
                
                check_vars_list_else_throw(vars);

                auto free = find_free(body, vars);
                auto sets = find_sets(body, vars);
                return collect_free(
                    free, e, 
                    m_code.new_vmx_close(
                        list_length(free),
                        make_boxes(
                            sets, vars,
                            compile_exp(
                                body,
                                m_code.new_vmx_return(list_length(vars)),
                                cons(&m_gc_tfe, vars, free),   // new env: (local . free)
                                set_union(sets, set_intersect(s, free))
                            )
                        ),
                        next
                    )
                );
            }
            else if (keyword_symbol_id == m_id_cache.if_) {
                // if
                auto args = extract_args<3>(tail);
                auto cond_code_obj = args[0];
                auto then_code_obj = args[1];
                auto else_code_obj = args[2];
                return compile_exp(
                    cond_code_obj,
                    m_code.new_vmx_test(
                        compile_exp(then_code_obj, next, e, s),
                        compile_exp(else_code_obj, next, e, s)
                    ),
                    e, s
                );
            }
            else if (keyword_symbol_id == m_id_cache.set) {
                // set!
                auto args = extract_args<2>(tail);
                auto var = args[0];
                auto x = args[1];   // we set the variable to this object, 'set' in past-tense
                assert(var.is_interned_symbol());
                
                auto [rel_var_scope, n] = compile_lookup(var, e);
                switch (rel_var_scope) {
                    case RelVarScope::Local: {
                        return compile_exp(x, m_code.new_vmx_assign_local(n, next), e, s);
                    } break;
                    case RelVarScope::Free: {
                        return compile_exp(x, m_code.new_vmx_assign_free(n, next), e, s);
                    } break;
                    default: {
                        error("Unknown RelVarScope");
                        throw SsiError();
                    }
                }
            }
            else if (keyword_symbol_id == m_id_cache.call_cc) {
                // call/cc
                // NOTE: procedure type check occurs in 'apply' later
                // SEE: p. 97

                auto args = extract_args<1>(tail);
                auto x = args[0];
                
                bool is_tail_call = is_tail_vmx(next);
                my_ssize_t m; 
                if (is_tail_call) {
                    assert(m_code[next].kind == VmExpKind::Return);
                    m = m_code[next].args.i_return.n;
                } else {
                    // 'm' unused
                }

                return m_code.new_vmx_frame(
                    // 'x' in three-imp, p.97
                    m_code.new_vmx_conti(
                        m_code.new_vmx_argument(
                            compile_exp(
                                x, 
                                (is_tail_call ? 
                                    m_code.new_vmx_shift(1, m, m_code.new_vmx_apply()) : 
                                    m_code.new_vmx_apply()), 
                                e, s
                            )
                        )
                    ),

                    // 'ret' in three-imp, p.97
                    next
                );
            } 
            // else if (keyword_symbol_id == m_builtin_intstr_id_cache.define) {
            //     // define
            //     auto args = extract_args<2>(args);
            //     auto structural_signature = args[0];
            //     auto body = args[1];
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
            else if (keyword_symbol_id == m_id_cache.begin) {
                // (begin expr ...+)

                // ensuring at least one argument is provided:
                if (tail.is_null()) {
                    error("begin: expected at least one expression form to evaluate, got 0.");
                    throw SsiError();
                }

                // assembling each code object on a stack to translate in reverse order:
                std::vector<OBJECT> obj_stack;
                obj_stack.reserve(32);
                OBJECT rem_args = tail;
                while (!rem_args.is_null()) {
                    obj_stack.push_back(car(rem_args));
                    rem_args = cdr(rem_args);
                }

                // compiling arguments from last to first, linking:
                VmExpID final_begin_instruction = next;
                while (!obj_stack.empty()) {
                    final_begin_instruction = compile_exp(obj_stack.back(), final_begin_instruction, e, s);
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
            bool is_tail_call = is_tail_vmx(next);
            my_ssize_t m;
            if (is_tail_call) {
                assert(m_code[next].kind == VmExpKind::Return);
                m = m_code[next].args.i_return.n;
            }
            VmExpID next_c = compile_exp(
                head, 
                (is_tail_call ?
                    m_code.new_vmx_shift(list_length(obj->cdr()), m, m_code.new_vmx_apply()) :
                    m_code.new_vmx_apply()), 
                e, s
            );
            OBJECT rem_args = tail;
            for (;;) {
                if (rem_args.is_null()) {
                    return 
                        (is_tail_call ?
                            next_c :
                            m_code.new_vmx_frame(next_c, next));        // new_vmx_frame(x, ret)
                } else {
                    next_c = compile_exp(
                        car(rem_args),
                        m_code.new_vmx_argument(next_c),
                        e, s
                    );
                    rem_args = cdr(rem_args);
                }
            }
        }

        // unreachable
    }
    VmExpID Compiler::compile_refer(OBJECT x, OBJECT e, VmExpID next) {
        auto [rel_scope, n] = compile_lookup(x, e);
        switch (rel_scope) {
            case RelVarScope::Local: {
                return m_code.new_vmx_refer_local(n, next);
            } break;
            case RelVarScope::Free: {
                return m_code.new_vmx_refer_free(n, next);
            } break;
            case RelVarScope::Global: {
                error("NotImplemented: RelVarScope::Global");
                throw SsiError();
            } break;
            default: {
                error("NotImplemented: unknown RelVarScope");
                throw SsiError();
            }
        }
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
    VmExpID Compiler::collect_free(OBJECT vars, OBJECT e, VmExpID next) {
        if (vars.is_null()) {
            return next;
        } else {
            return collect_free(
                cdr(vars), e,
                compile_refer(car(vars), e, m_code.new_vmx_argument(next))
            );
        }
    }
    VmExpID Compiler::make_boxes(OBJECT sets, OBJECT vars, VmExpID next) {
        // see three-imp p.102
        // NOTE: 'box' instructions are generated in reverse-order vs. in
        // three-imp, aligning with tail-position: indices used in 'box' 
        // instruction do not change: car(vars) indexed 0, ...
        size_t n = 0;
        VmExpID x = next;
        for (size_t n = 0; !vars.is_null(); (++n, vars=cdr(vars))) {
            if (is_set_member(car(vars), sets)) {
                x = m_code.new_vmx_box(n, x);
            }
        }
        return x;
    }

    /// Scheme Set functions
    //

    bool Compiler::is_set_member(OBJECT x, OBJECT s) {
        if (s.is_null()) {
            return false;
        }
        if (is_eq(&m_gc_tfe, x, car(s))) {
            return true;
        }
        return is_set_member(x, cdr(s));
    }
    OBJECT Compiler::set_cons(OBJECT x, OBJECT s) {
        if (is_set_member(x, s)) {
            return s;
        } else {
            return cons(&m_gc_tfe, x, s);
        }
    }
    OBJECT Compiler::set_union(OBJECT s1, OBJECT s2) {
        if (s1.is_null()) {
            return s2;
        } else {
            return set_union(cdr(s1), set_cons(car(s1), s2));
        }
    }
    OBJECT Compiler::set_minus(OBJECT s1, OBJECT s2) {
        if (s1.is_null()) {
            return OBJECT::make_null();
        } else if (is_set_member(car(s1), s2)) {
            return set_minus(cdr(s1), s2);
        } else {
            return cons(&m_gc_tfe, car(s1), set_minus(cdr(s1), s2));
        }
    }
    OBJECT Compiler::set_intersect(OBJECT s1, OBJECT s2) {
        if (s1.is_null()) {
            return OBJECT::make_null();
        } else if (is_set_member(car(s1), s2)) {
            return cons(&m_gc_tfe, car(s1), set_intersect(cdr(s1), s2));
        } else {
            return set_intersect(cdr(s1), s2);
        }
    }

    /// Find-Free
    //

    OBJECT Compiler::find_free(OBJECT x, OBJECT b) {
        // main case:
        if (x.is_interned_symbol()) {
            if (is_set_member(x, b)) {
                return OBJECT::make_null();
            } else {
                return list(&m_gc_tfe, x);
            }
        }

        // structural recursion:
        else if (x.is_pair()) {
            OBJECT head = car(x);
            OBJECT tail = cdr(x);

            // checking if builtin:
            if (head.is_interned_symbol()) {
                auto head_symbol = head.as_interned_symbol();
                if (head_symbol == m_id_cache.quote) {
                    return OBJECT::make_null();
                }
                else if (head_symbol == m_id_cache.lambda) {
                    auto args = extract_args<2>(tail);
                    auto vars = args[0];
                    auto body = args[1];
                    return find_free(body, set_union(vars, b));
                }
                else if (head_symbol == m_id_cache.if_) {
                    auto args = extract_args<3>(tail);
                    auto cond = args[0];
                    auto then = args[1];
                    auto else_ = args[2];
                    return set_union(
                        find_free(cond, b),
                        set_union(
                            find_free(then, b),
                            find_free(else_, b)
                        )
                    );
                }
                else if (head_symbol == m_id_cache.set) {
                    auto args = extract_args<2>(tail);
                    auto var = args[0];
                    auto exp = args[1];
                    return set_union(
                        (is_set_member(var, b) ? OBJECT::make_null() : list(&m_gc_tfe, var)),
                        find_free(exp, b)
                    );
                }
                else if (head_symbol == m_id_cache.call_cc) {
                    auto args = extract_args<1>(tail);
                    auto exp = args[0];
                    return find_free(exp, b);
                }
                else if (head_symbol == m_id_cache.begin) {
                    OBJECT rem_args = tail;
                    OBJECT res = OBJECT::make_null();
                    while (!rem_args.is_null()) {
                        OBJECT const head_exp = car(rem_args);
                        // TODO: if 'head_exp' is 'define', it should be added to 'b' here.
                        res = set_union(res, find_free(head_exp, b));
                        rem_args = cdr(rem_args);
                    }
                    return res;
                } else {
                    // continue to below block...
                }
            }
            
            // otherwise, function call, so recurse through function and arguments:
            {
                OBJECT rem = x;
                OBJECT res = OBJECT::make_null();
                for (;;) {
                    if (rem.is_null()) {
                        return res;
                    } else {
                        res = set_union(res, find_free(car(rem), b));
                        rem = cdr(rem);
                    }
                }
            }
        }
        else {
            return OBJECT::make_null();
        }
    }

    OBJECT Compiler::find_sets(OBJECT x, OBJECT v) {
        // cf p.101 of three-imp

        // individual variables:
        {
            if (x.is_interned_symbol()) {
                return OBJECT::make_null();
            }
        }
        
        // builtin operators AND function calls:
        {
            if (x.is_pair()) {
                // maybe builtin operator?
                if (car(x).is_interned_symbol()) {
                    OBJECT head = car(x);
                    OBJECT tail = cdr(x);

                    IntStr head_name = head.as_interned_symbol();

                    if (head_name == m_id_cache.quote) {
                        return OBJECT::make_null();
                    }
                    if (head_name == m_id_cache.lambda) {
                        auto args = extract_args<2>(tail);
                        auto vars = args[0];
                        auto body = args[1];
                        find_sets(body, set_minus(v, vars));
                    }
                    if (head_name == m_id_cache.if_) {
                        auto args = extract_args<3>(tail);
                        auto test = args[0];
                        auto then = args[1];
                        auto else_ = args[2];
                        return set_union(
                            find_sets(test, v),
                            set_union(
                                find_sets(then, v),
                                find_sets(else_, v)
                            )
                        );
                    }
                    if (head_name == m_id_cache.set) {
                        auto args = ss::extract_args<2>(tail);
                        auto var = args[0];
                        auto x = args[1];
                        if (is_set_member(var, v)) {
                            return v;
                        } else {
                            return set_cons(var, v);
                        }
                    }
                    if (head_name == m_id_cache.call_cc) {
                        auto args = ss::extract_args<1>(tail);
                        auto exp = args[0];
                        return find_sets(exp, v);
                    }
                    if (head_name == m_id_cache.begin) {
                        OBJECT rem_args = tail;
                        OBJECT res = OBJECT::make_null();
                        while (!rem_args.is_null()) {
                            OBJECT const head_exp = car(rem_args);
                            // TODO: if 'head_exp' is 'define', it should be added to 'b' here.
                            res = set_union(res, find_sets(head_exp, v));
                            rem_args = cdr(rem_args);
                        }
                        return res;
                    }
                }

                // else function call: get 'set!'s in each term
                OBJECT rem = x;
                OBJECT res = OBJECT::make_null();
                for (;;) {
                    if (rem.is_null()) {
                        break;
                    } else {
                        res = set_union(find_sets(car(rem), v), res);
                        rem = cdr(rem);
                    }
                }
            }
        }

        // everything else
        {
            return OBJECT::make_null();
        }
    }
    
}