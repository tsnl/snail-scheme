#include "ss-core/compiler.hh"

#include <utility>
#include "ss-core/printing.hh"
#include "ss-core/common.hh"
#include "ss-core/object.hh"
#include "ss-core/feedback.hh"

namespace ss {

    constexpr gc::SizeClassIndex vcode_sci = gc::sci(sizeof(VCode));

    Compiler::Compiler(GcThreadFrontEnd& gc_tfe) 
    :   Analyst(),
        m_code(new(gc_tfe.allocate_size_class(vcode_sci)) VCode()),
        m_gc_tfe(gc_tfe),
        m_gdef_set(OBJECT::null)
    {}

    VSubr Compiler::compile_expr(std::string subr_name, OBJECT expr_datum) {
        std::vector<OBJECT> line_code_objects{1, expr_datum};
        return compile_subr(std::move(subr_name), std::move(line_code_objects));
    }
    VSubr Compiler::compile_subr(std::string subr_name, std::vector<OBJECT> line_code_objects) {
        std::vector<VmProgram> line_programs;
        line_programs.reserve(line_code_objects.size());
        for (auto const code_object: line_code_objects) {
            // convert 'syntax' object into datum before compiling, discarding line info
            // if passes previous pass, then only runtime errors can be generated
            auto datum_code_object = code_object;
            if (code_object.is_syntax()) {
                datum_code_object = code_object.as_syntax_p()->to_datum(&m_gc_tfe);
                // std::cerr 
                //     << "syntax->datum: " << std::endl
                //     << "syntax: " << code_object << std::endl
                //     << "datum:  " << datum_code_object << std::endl;
            }
            auto program = compile_line(datum_code_object);
            line_programs.push_back(program);
        }
        return VSubr{std::move(subr_name), std::move(line_code_objects), std::move(line_programs)};
    }
    VmProgram Compiler::compile_line(OBJECT line_code_obj) {
        VmExpID last_exp_id = m_code->new_vmx_halt();
        VmExpID res = compile_exp(line_code_obj, last_exp_id);
        return {res, last_exp_id};
    }
    VmExpID Compiler::compile_exp(OBJECT x, VmExpID next) {
        // iteratively translating this line to a VmProgram
        //  - cf p. 87 of 'three-imp.pdf', §4.3.2: Translation and Evaluation
        switch (obj_kind(x)) {
            case ObjectKind::InternedSymbol: {
                // return decode_nonlocal(
                //     x, e, 
                //     (is_set_member(x, s) ? m_code->new_vmx_indirect(next) : next)
                // );
                std::stringstream ss;
                ss << "CompilerError: found unexpected un-expanded symbol: ";
                ss << interned_string(x.as_symbol());
                error(ss.str());
                throw SsiError();
            }
            case ObjectKind::Pair: {
                return compile_list_exp(x.as_pair_p(), next);
            }
            default: {
                return m_code->new_vmx_constant(x, next);
            }
        }
    }
    VmExpID Compiler::compile_list_exp(PairObject* obj, VmExpID next) {
        // corresponds to 'record-case' in three-imp

        // retrieving key properties:
        OBJECT head = obj->car();
        OBJECT tail = obj->cdr();

        // first, trying to handle a builtin function invocation:
        if (head.is_symbol()) {
            // keyword first argument => may be builtin
            auto keyword_symbol_id = head.as_symbol();

            // quote
            if (keyword_symbol_id == g_id_cache().quote) {
                auto quoted = extract_args<1>(tail)[0];
                return m_code->new_vmx_constant(quoted, next);
            }
            
            // expanded-lambda
            else if (keyword_symbol_id == g_id_cache().expanded_lambda) {
                auto args = extract_args<3>(tail);
                auto vars = args[0];
                auto free = args[1];
                auto body = args[2];
                
                // NOTE: We make boxes for vars only, not free. 
                // cf three-imp p.101.

                return collect_free(
                    free,
                    m_code->new_vmx_close(
                        list_length(free),
                        make_boxes(
                            vars,
                            compile_exp(
                                body,
                                m_code->new_vmx_return(list_length(vars))
                            )
                        ),
                        next
                    )
                );
            }

            // lambda
            // else if (keyword_symbol_id == g_id_cache().lambda) {
            //     auto args = extract_args<2>(tail);
            //     auto vars = args[0];
            //     auto body = args[1];
                
            //     // check_vars_list_else_throw(std::move(loc), vars);

            //     auto free = set_minus(find_free(body, vars), m_gdef_set);
            //     auto sets = find_sets(body, vars);
            //     return collect_free(
            //         free, e, 
            //         m_code->new_vmx_close(
            //             list_length(free),
            //             make_boxes(
            //                 sets, vars,
            //                 compile_exp(
            //                     body,
            //                     m_code->new_vmx_return(list_length(vars)),
            //                     cons(&m_gc_tfe, vars, free),   // new env: (local . free)
            //                     set_union(sets, set_intersect(s, free))
            //                 )
            //             ),
            //             next
            //         )
            //     );
            // }

            // if
            else if (keyword_symbol_id == g_id_cache().if_) {
                auto args = extract_args<3>(tail);
                auto cond_code_obj = args[0];
                auto then_code_obj = args[1];
                auto else_code_obj = args[2];
                return compile_exp(
                    cond_code_obj,
                    m_code->new_vmx_test(
                        compile_exp(then_code_obj, next),
                        compile_exp(else_code_obj, next)
                    )
                );
            }

            // // set!
            // else if (keyword_symbol_id == g_id_cache().set) {
            //     auto args = extract_args<2>(tail);
            //     auto var = args[0];
            //     auto x = args[1];   // we set the variable to this object, 'set' in past-tense
            //     assert(var.is_symbol());
                
            //     auto [rel_var_scope, n] = compile_lookup(var);
            //     switch (rel_var_scope) {
            //         case RelVarScope::Local: {
            //             return compile_exp(x, m_code->new_vmx_assign_local(n, next), s);
            //         } break;
            //         case RelVarScope::Free: {
            //             return compile_exp(x, m_code->new_vmx_assign_free(n, next), s);
            //         } break;
            //         case RelVarScope::Global: {
            //             return compile_exp(x, m_code->new_vmx_assign_global(n, next), s);
            //         } break;
            //         default: {
            //             error("set!: unknown RelVarScope");
            //             throw SsiError();
            //         }
            //     }
            // }

            // call/cc
            else if (keyword_symbol_id == g_id_cache().call_cc) {
                // NOTE: procedure type check occurs in 'apply' later
                // SEE: p. 97

                auto args = extract_args<1>(tail);
                auto x = args[0];
                
                bool is_tail_call = is_tail_vmx(next);
                ssize_t m; 
                if (is_tail_call) {
                    assert((*m_code)[next].kind == VmExpKind::Return);
                    m = (*m_code)[next].args.i_return.n;
                } else {
                    // 'm' unused
                }

                return m_code->new_vmx_frame(
                    // 'x' in three-imp, p.97
                    m_code->new_vmx_conti(
                        m_code->new_vmx_argument(
                            compile_exp(
                                x, 
                                (is_tail_call ? 
                                    m_code->new_vmx_shift(1, m, m_code->new_vmx_apply()) : 
                                    m_code->new_vmx_apply())
                            )
                        )
                    ),

                    // 'ret' in three-imp, p.97
                    next
                );
            } 

            // expanded-define
            else if (keyword_symbol_id == g_id_cache().expanded_define) {
                auto args = extract_args<3>(tail);
                auto scope_sym_obj = args[0];
                auto name = args[1];
                auto body = args[2];
                
                assert(scope_sym_obj.is_symbol());
                assert(name.is_integer());

                auto scope_sym = scope_sym_obj.as_symbol();
                if (scope_sym == g_id_cache().global) {
                    GDefID gdef_id = static_cast<LDefID>(name.as_integer());
                    return compile_exp(
                        body,
                        m_code->new_vmx_assign_global(gdef_id, next)
                    );
                }
                if (scope_sym == g_id_cache().local) {
                    LDefID ldef_id = static_cast<LDefID>(name.as_integer());
                    return compile_exp(
                        body,
                        m_code->new_vmx_assign_local(ldef_id, next)
                    );
                }

                std::stringstream ss;
                ss << "expected scope symbol to be 'local', 'global', but got: " << scope_sym_obj << std::endl;
                error(ss.str());
                throw SsiError();
            }

            // p/invoke
            else if (keyword_symbol_id == g_id_cache().p_invoke) {
                auto proc_name = car(tail);
                auto proc_args = cdr(tail);
            
                if (!proc_name.is_integer()) {
                    std::stringstream ss;
                    ss << "Invalid args to 'p/invoke': expected first arg to be a symbol" << std::endl;
                    ss << "got: " << proc_name;
                    error(ss.str());
                    throw SsiError();
                }

                OBJECT rem_args = proc_args;
                ssize_t arg_count = list_length(rem_args);
                PlatformProcID platform_proc_idx = static_cast<PlatformProcID>(proc_name.as_integer());
                VmExpID next_body = m_code->new_vmx_pinvoke(
                    arg_count, platform_proc_idx,
                    next
                );

                ssize_t expected_arg_count = m_code->platform_proc_arity(platform_proc_idx);
                if (!m_code->platform_proc_is_variadic(platform_proc_idx)) {
                    if (arg_count != expected_arg_count) {
                        std::stringstream ss;
                        ss  << "Invalid argument count for 'p/invoke' " << interned_string(proc_name.as_symbol())
                            << ": expected " << expected_arg_count << " args but got " << arg_count << " args";
                        error(ss.str());
                    }                
                }
                
                // evaluating arguments in reverse order: first is 'next' of second, ...
                while (!rem_args.is_null()) {
                    next_body = compile_exp(
                        car(rem_args),
                        m_code->new_vmx_argument(next_body)
                    );
                    rem_args = cdr(rem_args);
                }
                return next_body;
            }

            // (begin expr ...+)
            else if (keyword_symbol_id == g_id_cache().begin) {
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
                    final_begin_instruction = compile_exp(obj_stack.back(), final_begin_instruction);
                    obj_stack.pop_back();
                }

                // returning:
                return final_begin_instruction;
            }

            // (reference ...)
            else if (keyword_symbol_id == g_id_cache().reference) {
                auto args = extract_args<2>(tail);
                OBJECT rel_var_scope_sym_obj = args[0];
                OBJECT def_id_obj = args[1];

                assert(rel_var_scope_sym_obj.is_symbol());
                IntStr rel_var_scope_sym = rel_var_scope_sym_obj.as_symbol();
                
                assert(def_id_obj.is_integer());
                ssize_t def_id = def_id_obj.as_integer();

                if (rel_var_scope_sym == g_id_cache().local) {
                    return m_code->new_vmx_refer_local(def_id, next);
                }
                if (rel_var_scope_sym == g_id_cache().free) {
                    return m_code->new_vmx_refer_free(def_id, next);
                }
                if (rel_var_scope_sym == g_id_cache().global) {
                    return m_code->new_vmx_refer_global(def_id, next);
                }

                error("Unknown rel_var_scope_sym: " + interned_string(rel_var_scope_sym));
                throw SsiError();
            }

            // (mutation ...)
            else if (keyword_symbol_id == g_id_cache().mutation) {
                error("NotImplemented: compiling 'mutation' terms");
                throw SsiError();
            }

            else {
                // continue to the branch below...
            }
        }

        // otherwise, apply (since all macros expanded)
        //  NOTE: the 'car' expression could be a non-symbol, e.g. a lambda expression for an IIFE
        {
            // function call
            bool is_tail_call = is_tail_vmx(next);
            ssize_t m;
            if (is_tail_call) {
                assert((*m_code)[next].kind == VmExpKind::Return);
                m = (*m_code)[next].args.i_return.n;
            }
            VmExpID next_body = compile_exp(
                head, 
                (is_tail_call ?
                    m_code->new_vmx_shift(list_length(obj->cdr()), m, m_code->new_vmx_apply()) :
                    m_code->new_vmx_apply())
            );
            OBJECT rem_args = tail;
            // evaluating arguments in reverse order: first is 'next' of second, ...
            while (!rem_args.is_null()) {
                next_body = compile_exp(
                    car(rem_args),
                    m_code->new_vmx_argument(next_body)
                );
                rem_args = cdr(rem_args);
            }
            // new_vmx_frame(body_x, post_ret_x) ---v
            return (is_tail_call ? next_body : m_code->new_vmx_frame(next_body, next));
        }

        // unreachable
    }
    VmExpID Compiler::refer_nonlocal(OBJECT x, VmExpID next) {
        // 'x' is a 'Nonlocal' list, cf expander
        auto nonlocal_array = extract_args<4>(x);
        OBJECT parent_rel_var_scope_sym_obj = nonlocal_array[0];
        OBJECT parent_idx_obj = nonlocal_array[1];
        OBJECT ldef_id_obj = nonlocal_array[2];
        OBJECT use_is_mut_obj = nonlocal_array[3];
        
        assert(parent_rel_var_scope_sym_obj.is_symbol());
        assert(parent_idx_obj.is_integer());
        assert(ldef_id_obj.is_integer());
        assert(use_is_mut_obj.is_boolean());

#if NDEBUG
        SUPPRESS_UNUSED_VARIABLE_WARNING(ldef_id_obj);
        SUPPRESS_UNUSED_VARIABLE_WARNING(use_is_mut_obj)
#endif

        IntStr parent_rel_var_scope_sym = parent_rel_var_scope_sym_obj.as_symbol();
        ssize_t parent_idx = parent_idx_obj.as_integer();
        // LDefID ldef_id = static_cast<LDefID>(ldef_id_obj.as_integer());
        // bool is_mut = use_is_mut_obj.as_boolean();

        if (parent_rel_var_scope_sym == g_id_cache().local) {
            return m_code->new_vmx_refer_local(parent_idx, next);
        }
        if (parent_rel_var_scope_sym == g_id_cache().free) {
            return m_code->new_vmx_refer_free(parent_idx, next);
        }
        if (parent_rel_var_scope_sym == g_id_cache().global) {
            return m_code->new_vmx_refer_global(parent_idx, next);
        }

        std::stringstream ss;
        ss << "NotImplemented: unknown RelVarScopeSym: " << parent_rel_var_scope_sym_obj << std::endl;
        error(ss.str());
        throw SsiError();
    }

    bool Compiler::is_tail_vmx(VmExpID vmx_id) {
        return (*m_code)[vmx_id].kind == VmExpKind::Return;
    }
    VmExpID Compiler::collect_free(OBJECT vars, VmExpID next) {
        // collecting in reverse-order vs. in three-imp
        if (vars.is_null()) {
            return next;
        } else {
            // collect each free var by (1) referring, and (2) passing as 
            // argument (hence pushing onto stack)
            return collect_free(
                cdr(vars),
                refer_nonlocal(
                    car(vars), 
                    m_code->new_vmx_argument(next)
                )
            );
        }
    }
    VmExpID Compiler::make_boxes(OBJECT vars, VmExpID next) {
        // see three-imp p.102
        // NOTE: 'box' instructions are generated in reverse-order vs. in
        // three-imp, aligning with tail-position: indices used in 'box' 
        // instruction do not change: car(vars) indexed 0, ...
        VmExpID x = next;
        for (size_t n = 0; !vars.is_null(); (++n, vars = cdr(vars))) {
            auto ldef_id_obj = car(vars);
            assert(ldef_id_obj.is_integer() && "Expected LDefID (int) for local var");
            auto ldef_id = ldef_id_obj.as_integer();
            auto ldef = m_code->def_tab().local(ldef_id);

            if (ldef.is_mutated()) {
                x = m_code->new_vmx_box(n, x);
            }
        }
        return x;
    }
    GDefID Compiler::define_global(FLoc loc, IntStr name, OBJECT code, OBJECT init, std::string docstring) {
        m_gdef_set = set_cons(OBJECT::make_symbol(name), m_gdef_set);
        return m_code->define_global(loc, name, code, init, docstring);
    }
    Definition const& Compiler::lookup_gdef(GDefID gdef_id) const {
        return m_code->global(gdef_id);
    }
    Definition const* Compiler::try_lookup_gdef_by_name(IntStr name) const {
        return m_code->try_lookup_gdef_by_name(name);
    }

    void Compiler::initialize_platform_globals(std::vector<OBJECT>& global_vals) {
        for (size_t i = 0; i < m_code->count_globals(); i++) {
            GDefID gdef_id = static_cast<GDefID>(i);
            Definition const& gdef = m_code->def_tab().global(gdef_id);
            global_vals[i] = gdef.init();
        }
    }

    // Globals:
    //

    PlatformProcID Compiler::define_platform_proc(
        IntStr platform_proc_name, 
        std::vector<std::string> arg_names, 
        PlatformProcCb callable_cb, 
        std::string docstring, 
        bool is_variadic
    ) {
        std::vector<IntStr> rw_arg_names;
        rw_arg_names.reserve(arg_names.size());
        for (auto const& s: arg_names) {
            rw_arg_names.push_back(intern(s));
        }
        return m_code->define_platform_proc(
            platform_proc_name, 
            std::move(rw_arg_names), 
            callable_cb, 
            std::move(docstring), 
            is_variadic
        );
    }
    PlatformProcID Compiler::lookup_platform_proc(IntStr name) {
        return m_code->lookup_platform_proc(name);
    }

    /// Scheme Set functions
    //

    bool Compiler::is_set_member(OBJECT x, OBJECT s) {
        if (s.is_null()) {
            return false;
        }
        if (is_eq(x, car(s))) {
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
            return OBJECT::null;
        } else if (is_set_member(car(s1), s2)) {
            return set_minus(cdr(s1), s2);
        } else {
            return cons(&m_gc_tfe, car(s1), set_minus(cdr(s1), s2));
        }
    }
    OBJECT Compiler::set_intersect(OBJECT s1, OBJECT s2) {
        if (s1.is_null()) {
            return OBJECT::null;
        } else if (is_set_member(car(s1), s2)) {
            return cons(&m_gc_tfe, car(s1), set_intersect(cdr(s1), s2));
        } else {
            return set_intersect(cdr(s1), s2);
        }
    }

    /// Find-Free
    // NOTE: includes globals, must remove explicitly later
    //

    OBJECT Compiler::find_free(OBJECT x, OBJECT b) {
        // main case:
        if (x.is_symbol()) {
            if (is_set_member(x, b)) {
                return OBJECT::null;
            } else {
                return list(&m_gc_tfe, x);
            }
        }

        // structural recursion:
        else if (x.is_pair()) {
            OBJECT head = car(x);
            OBJECT tail = cdr(x);

            // checking if builtin:
            if (head.is_symbol()) {
                auto head_symbol = head.as_symbol();
                if (head_symbol == g_id_cache().quote) {
                    return OBJECT::null;
                }
                else if (head_symbol == g_id_cache().lambda) {
                    auto args = extract_args<2>(tail);
                    auto vars = args[0];
                    auto body = args[1];
                    return find_free(body, set_union(vars, b));
                }
                else if (head_symbol == g_id_cache().if_) {
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
                else if (head_symbol == g_id_cache().set) {
                    auto args = extract_args<2>(tail);
                    auto var = args[0];
                    auto exp = args[1];
                    return set_union(
                        (is_set_member(var, b) ? OBJECT::null : list(&m_gc_tfe, var)),
                        find_free(exp, b)
                    );
                }
                else if (head_symbol == g_id_cache().call_cc) {
                    auto args = extract_args<1>(tail);
                    auto exp = args[0];
                    return find_free(exp, b);
                }
                else if (head_symbol == g_id_cache().begin) {
                    OBJECT rem_args = tail;
                    OBJECT res = OBJECT::null;
                    while (!rem_args.is_null()) {
                        OBJECT const head_exp = car(rem_args);
                        // TODO: if 'head_exp' is 'define', it should be added to 'b' here.
                        res = set_union(res, find_free(head_exp, b));
                        rem_args = cdr(rem_args);
                    }
                    return res;
                } 
                
                // p/invoke
                else if (head_symbol == g_id_cache().p_invoke) {
                    OBJECT res = OBJECT::null;
                    OBJECT rem_args = cdr(tail);
                    while (!rem_args.is_null()) {
                        OBJECT const head_exp = car(rem_args);
                        res = set_union(res, find_free(head_exp, b));
                        rem_args = cdr(rem_args);
                    }
                    return res;
                } 
                
                else {
                    // continue to below block...
                }
            }
            
            // otherwise, function call, so recurse through function and arguments:
            {
                OBJECT rem = x;
                OBJECT res = OBJECT::null;
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
            return OBJECT::null;
        }
    }

    OBJECT Compiler::find_sets(OBJECT x, OBJECT v) {
        // cf p.101 of three-imp

        // individual variables:
        {
            if (x.is_symbol()) {
                return OBJECT::null;
            }
        }
        
        // builtin operators AND function calls:
        {
            if (x.is_pair()) {
                // maybe builtin operator?
                if (car(x).is_symbol()) {
                    OBJECT head = car(x);
                    OBJECT tail = cdr(x);

                    IntStr head_name = head.as_symbol();

                    if (head_name == g_id_cache().quote) {
                        return OBJECT::null;
                    }
                    if (head_name == g_id_cache().lambda) {
                        auto args = extract_args<2>(tail);
                        auto vars = args[0];
                        auto body = args[1];
                        find_sets(body, set_minus(v, vars));
                    }
                    if (head_name == g_id_cache().if_) {
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
                    if (head_name == g_id_cache().set) {
                        auto args = ss::extract_args<2>(tail);
                        auto var = args[0];
                        if (is_set_member(var, v)) {
                            return v;
                        } else {
                            return set_cons(var, v);
                        }
                    }
                    if (head_name == g_id_cache().call_cc) {
                        auto args = ss::extract_args<1>(tail);
                        auto exp = args[0];
                        return find_sets(exp, v);
                    }
                    if (head_name == g_id_cache().begin) {
                        OBJECT rem_args = tail;
                        OBJECT res = OBJECT::null;
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
                OBJECT res = OBJECT::null;
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
            return OBJECT::null;
        }
    }
    
}