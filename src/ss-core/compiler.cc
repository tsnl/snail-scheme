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
     
    // returns [n, m] = [rib_index, elt_index]
    std::pair<RelVarScope, size_t> Compiler::compile_lookup(OBJECT symbol, OBJECT var_env) {
        // compile-time type-checks
        bool ok = (
            (var_env.is_pair() && "broken 'env' in compile_lookup: expected pair") &&
            (symbol.is_interned_symbol() && "broken query symbol in compile_lookup: expected symbol")
        );
        if (!ok) {
            throw SsiError();
        }

        // // DEBUG:
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
            
            while (!free.is_null()) {
                if (ss::is_eq(&m_gc_tfe, car(free), symbol)) {
                    return {RelVarScope::Free, n};
                }
                // preparing for the next iteration:
                free = cdr(free);
                ++n;
            }
        }
        
        // checking globals
        {
            IntStr sym = symbol.as_interned_symbol();
            auto& gdef_id_symtab = m_code->gdef_id_symtab();
            auto it = gdef_id_symtab.find(sym);
            if (it != gdef_id_symtab.end()) {
                return {RelVarScope::Global, it->second};
            }
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

    VSubr Compiler::compile_subr_1shot(std::string subr_name, OBJECT line_code_object) {
        std::vector<OBJECT> line_code_objects{1, line_code_object};
        return compile_subr(std::move(subr_name), std::move(line_code_objects));
    }
    VSubr Compiler::compile_subr(std::string subr_name, std::vector<OBJECT> line_code_objects) {
        std::vector<VmProgram> line_programs;
        OBJECT const default_env = ss::cons(&m_gc_tfe, OBJECT::null, OBJECT::null);
        line_programs.reserve(line_code_objects.size());
        for (auto const code_object: line_code_objects) {
            // FIXME: (hacky): convert 'syntax' object into datum before compiling
            auto datum_code_object = code_object;
            if (code_object.is_syntax()) {
                datum_code_object = static_cast<SyntaxObject*>(code_object.as_ptr())->to_datum(&m_gc_tfe);
            }
            auto program = compile_line(datum_code_object, default_env);
            line_programs.push_back(program);
        }
        return VSubr{std::move(subr_name), std::move(line_code_objects), std::move(line_programs)};
    }
    VmProgram Compiler::compile_line(OBJECT line_code_obj, OBJECT var_e) {
        OBJECT s = OBJECT::null;     // empty set
        VmExpID last_exp_id = m_code->new_vmx_halt();
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
                    (is_set_member(x, s) ? m_code->new_vmx_indirect(next) : next)
                );
            }
            case GranularObjectType::Pair: {
                return compile_list_exp(static_cast<PairObject*>(x.as_ptr()), next, e, s);
            }
            default: {
                return m_code->new_vmx_constant(x, next);
            }
        }
    }
    VmExpID Compiler::compile_list_exp(PairObject* obj, VmExpID next, OBJECT e, OBJECT s) {
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
                return m_code->new_vmx_constant(quoted, next);
            }
            else if (keyword_symbol_id == m_id_cache.lambda) {
                // lambda
                auto args = extract_args<2>(tail);
                auto vars = args[0];
                auto body = args[1];
                
                check_vars_list_else_throw(vars);

                auto free = set_minus(find_free(body, vars), m_gdef_set);
                auto sets = set_intersect(find_sets(body, vars), free);
                return collect_free(
                    free, e, 
                    m_code->new_vmx_close(
                        list_length(free),
                        make_boxes(
                            sets, vars,
                            compile_exp(
                                body,
                                m_code->new_vmx_return(list_length(vars)),
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
                    m_code->new_vmx_test(
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
                        return compile_exp(x, m_code->new_vmx_assign_local(n, next), e, s);
                    } break;
                    case RelVarScope::Free: {
                        return compile_exp(x, m_code->new_vmx_assign_free(n, next), e, s);
                    } break;
                    case RelVarScope::Global: {
                        return compile_exp(x, m_code->new_vmx_assign_global(n, next), e, s);
                    } break;
                    default: {
                        error("set!: unknown RelVarScope");
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
                                    m_code->new_vmx_apply()), 
                                e, s
                            )
                        )
                    ),

                    // 'ret' in three-imp, p.97
                    next
                );
            } 
            else if (keyword_symbol_id == m_id_cache.define) {
                // define
                auto args = extract_args<2>(tail);
                auto structural_signature = args[0];
                auto body = args[1];
                auto name = OBJECT::null;
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
                assert(name.is_interned_symbol());
                IntStr name_sym = name.as_interned_symbol();
                GDefID gdef_id = define_global(name_sym);
                if (pattern_ok) {
                    return compile_exp(
                        body,
                        m_code->new_vmx_assign_global(gdef_id, next),
                        e, s
                    );
                } else {
                    error("Invalid args to 'define'");
                    throw SsiError();
                }
            }
            else if (keyword_symbol_id == m_id_cache.p_invoke) {
                // p/invoke
                auto proc_name = car(tail);
                auto proc_args = cdr(tail);
            
                if (!proc_name.is_interned_symbol()) {
                    error("Invalid args to 'p/invoke': expected first arg to be a symbol");
                    throw SsiError();
                }

                OBJECT rem_args = proc_args;
                my_ssize_t arg_count = list_length(rem_args);
                PlatformProcID platform_proc_idx = lookup_platform_proc(proc_name.as_interned_symbol());
                VmExpID next_body = m_code->new_vmx_pinvoke(
                    arg_count, platform_proc_idx,
                    next
                );

                size_t expected_arg_count = m_code->platform_proc_arity(platform_proc_idx);
                if (!m_code->platform_proc_is_variadic(platform_proc_idx)) {
                    if (arg_count != expected_arg_count) {
                        std::stringstream ss;
                        ss  << "Invalid argument count for 'p/invoke' " << interned_string(proc_name.as_interned_symbol())
                            << ": expected " << expected_arg_count << " args but got " << arg_count << " args";
                        error(ss.str());
                    }                
                }
                
                // evaluating arguments in reverse order: first is 'next' of second, ...
                while (!rem_args.is_null()) {
                    next_body = compile_exp(
                        car(rem_args),
                        m_code->new_vmx_argument(next_body),
                        e, s
                    );
                    rem_args = cdr(rem_args);
                }
                return next_body;
            }
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
                assert((*m_code)[next].kind == VmExpKind::Return);
                m = (*m_code)[next].args.i_return.n;
            }
            VmExpID next_body = compile_exp(
                head, 
                (is_tail_call ?
                    m_code->new_vmx_shift(list_length(obj->cdr()), m, m_code->new_vmx_apply()) :
                    m_code->new_vmx_apply()), 
                e, s
            );
            OBJECT rem_args = tail;
            // evaluating arguments in reverse order: first is 'next' of second, ...
            while (!rem_args.is_null()) {
                next_body = compile_exp(
                    car(rem_args),
                    m_code->new_vmx_argument(next_body),
                    e, s
                );
                rem_args = cdr(rem_args);
            }
            // new_vmx_frame(body_x, post_ret_x) ---v
            return (is_tail_call ? next_body : m_code->new_vmx_frame(next_body, next));
        }

        // unreachable
    }
    VmExpID Compiler::compile_refer(OBJECT x, OBJECT e, VmExpID next) {
        auto [rel_scope, n] = compile_lookup(x, e);
        switch (rel_scope) {
            case RelVarScope::Local: {
                return m_code->new_vmx_refer_local(n, next);
            } break;
            case RelVarScope::Free: {
                return m_code->new_vmx_refer_free(n, next);
            } break;
            case RelVarScope::Global: {
                return m_code->new_vmx_refer_global(n, next);
            } break;
            default: {
                error("NotImplemented: unknown RelVarScope");
                throw SsiError();
            }
        }
    }

    bool Compiler::is_tail_vmx(VmExpID vmx_id) {
        return (*m_code)[vmx_id].kind == VmExpKind::Return;
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
        // collecting in reverse-order
        if (vars.is_null()) {
            return next;
        } else {
            // collect each free var by (1) referring, and (2) passing as argument
            // (hence pushing onto stack)
            return collect_free(
                cdr(vars), e,
                compile_refer(car(vars), e, m_code->new_vmx_argument(next))
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
                x = m_code->new_vmx_box(n, x);
            }
        }
        return x;
    }
    GDefID Compiler::define_global(IntStr name, OBJECT code, OBJECT init, std::string docstring) {
        m_gdef_set = set_cons(OBJECT::make_interned_symbol(name), m_gdef_set);
        return m_code->define_global(name, code, init, docstring);
    }
    GDef const& Compiler::lookup_gdef(GDefID gdef_id) const {
        return m_code->lookup_gdef(gdef_id);
    }
    GDef const* Compiler::try_lookup_gdef_by_name(IntStr name) const {
        return m_code->try_lookup_gdef_by_name(name);
    }

    void Compiler::initialize_platform_globals(std::vector<OBJECT>& global_vals) {
        for (size_t i = 0; i < m_code->gdef_table().size(); i++) {
            GDef const& gdef = m_code->gdef_table()[i];
            global_vals[i] = gdef.init();
        }
    }

    // Globals:
    //

    PlatformProcID Compiler::define_platform_proc(
        IntStr platform_proc_name, 
        size_t arity, 
        PlatformProcCb callable_cb, 
        std::string docstring, 
        bool is_variadic
    ) {
        return m_code->define_platform_proc(platform_proc_name, arity, callable_cb, std::move(docstring), is_variadic);
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
        if (x.is_interned_symbol()) {
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
            if (head.is_interned_symbol()) {
                auto head_symbol = head.as_interned_symbol();
                if (head_symbol == m_id_cache.quote) {
                    return OBJECT::null;
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
                        (is_set_member(var, b) ? OBJECT::null : list(&m_gc_tfe, var)),
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
                    OBJECT res = OBJECT::null;
                    while (!rem_args.is_null()) {
                        OBJECT const head_exp = car(rem_args);
                        // TODO: if 'head_exp' is 'define', it should be added to 'b' here.
                        res = set_union(res, find_free(head_exp, b));
                        rem_args = cdr(rem_args);
                    }
                    return res;
                } else if (head_symbol == m_id_cache.p_invoke) {
                    OBJECT res = OBJECT::null;
                    OBJECT rem_args = cdr(tail);
                    while (!rem_args.is_null()) {
                        OBJECT const head_exp = car(rem_args);
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
            if (x.is_interned_symbol()) {
                return OBJECT::null;
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
                        return OBJECT::null;
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