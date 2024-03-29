#include "ss-core/vcode.hh"
#include <iomanip>
#include <sstream>
#include <cmath>

#include "ss-core/printing.hh"

namespace ss {

    /// VCode:
    //
    VCode::VCode(size_t file_count)
    :   m_exps(), 
        m_subrs(),
        m_def_tab(),
        m_pproc_tab()
    {
        size_t expected_num_defs = file_count * 100;
        m_exps.reserve(4096);
        m_subrs.reserve(expected_num_defs);
    }
    void VCode::enqueue_main_subr(std::string const& file_name, VSubr&& script) {
        assert(script.line_code_objs.size() == script.line_programs.size());

        bool is_empty = true;

        if (!script.line_programs.empty()) {
            // storing the input lines and the programs on this VM:
            m_subrs.push_back(std::move(script));
            is_empty = false;
        }
        if (is_empty) {
            warning(std::string("VM: Input file `") + file_name + "` is empty.");
        }
    }
    VCode::VCode(VCode&& other) noexcept
    :   m_exps(std::move(other.m_exps)),
        m_subrs(std::move(other.m_subrs)) 
    {}
    GDefID VCode::define_global(FLoc loc, IntStr name, OBJECT code, OBJECT init, std::string docstring) {
        return m_def_tab.define_global(loc, name, code, init, std::move(docstring));
    }
    Definition const& VCode::global(GDefID gdef_id) const {
        return m_def_tab.global(gdef_id);
    }
    Definition const* VCode::try_lookup_gdef_by_name(IntStr name) const {
        auto opt_res = m_def_tab.lookup_global_id(name);
        if (!opt_res.has_value()) {
            return nullptr;
        } else {
            return &global(opt_res.value());
        }
    }

    // Platform procedures:
    //

    PlatformProcID VCode::define_platform_proc(
        IntStr platform_proc_name, 
        std::vector<IntStr> arg_names,
        PlatformProcCb callable_cb, 
        std::string docstring,
        bool is_variadic
    ) {
        return m_pproc_tab.define(
            platform_proc_name,
            std::move(arg_names),
            std::move(callable_cb),
            std::move(docstring),
            is_variadic
        );
    }
    PlatformProcID VCode::lookup_platform_proc(IntStr platform_proc_name) {
        auto opt_res = m_pproc_tab.lookup(platform_proc_name);
        if (!opt_res.has_value()) {
            error("Undefined platform procedure used: " + interned_string(platform_proc_name));
            throw SsiError();
        }
        return opt_res.value();
    }


    /// Creating VM Expressions:
    //
    std::pair<VmExpID, VmExp&> VCode::help_new_vmx(VmExpKind kind) {
        VmExpID exp_id = m_exps.size();
        VmExp& exp_ref = m_exps.emplace_back(kind);
        return {exp_id, exp_ref};
    }
    VmExpID VCode::new_vmx_halt() {
        return help_new_vmx(VmExpKind::Halt).first;
    }
    VmExpID VCode::new_vmx_refer_local(size_t n, VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::ReferLocal);
        auto& args = exp_ref.args.i_refer;
        args.n = n;
        args.x = x;
        return exp_id;
    }
    VmExpID VCode::new_vmx_refer_free(size_t n, VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::ReferFree);
        auto& args = exp_ref.args.i_refer;
        args.n = n;
        args.x = x;
        return exp_id;
    }
    VmExpID VCode::new_vmx_refer_global(size_t n, VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::ReferGlobal);
        auto& args = exp_ref.args.i_refer;
        args.n = n;
        args.x = x;
        return exp_id;
    }
    VmExpID VCode::new_vmx_constant(OBJECT constant, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Constant);
        auto& args = exp_ref.args.i_constant;
        args.obj = constant;
        args.x = next;
        return exp_id;
    }
    VmExpID VCode::new_vmx_close(size_t vars_count, VmExpID body, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Close);
        auto& args = exp_ref.args.i_close;
        args.vars_count = vars_count;
        args.body = body;
        args.x = next;
        return exp_id;
    }
    VmExpID VCode::new_vmx_test(VmExpID next_if_t, VmExpID next_if_f) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Test);
        auto& args = exp_ref.args.i_test;
        args.next_if_t = next_if_t;
        args.next_if_f = next_if_f;
        return exp_id;
    }
    VmExpID VCode::new_vmx_conti(VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Conti);
        auto& args = exp_ref.args.i_conti;
        args.x = x;
        return exp_id;
    }
    VmExpID VCode::new_vmx_nuate(OBJECT stack, VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Nuate);
        auto& args = exp_ref.args.i_nuate;
        args.stack = stack;
        args.x = x;
        return exp_id;
    }
    VmExpID VCode::new_vmx_frame(VmExpID fn_body_x, VmExpID post_ret_x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Frame);
        auto& args = exp_ref.args.i_frame;
        args.fn_body_x = fn_body_x;
        args.post_ret_x = post_ret_x;
        return exp_id;
    }
    VmExpID VCode::new_vmx_argument(VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Argument);
        auto& args = exp_ref.args.i_argument;
        args.x = x;
        return exp_id;
    }
    VmExpID VCode::new_vmx_apply() {
        return help_new_vmx(VmExpKind::Apply).first;
    }
    VmExpID VCode::new_vmx_return(size_t n) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Return);
        auto& args = exp_ref.args.i_return;
        args.n = n;
        return exp_id;
    }
    VmExpID VCode::new_vmx_define(OBJECT var, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Define);
        auto& args = exp_ref.args.i_define;
        args.var = var;
        args.next = next;
        return exp_id;
    }
    VmExpID VCode::new_vmx_box(ssize_t n, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Box);
        auto& args = exp_ref.args.i_box;
        args.n = n;
        args.x = next;
        return exp_id;
    }
    VmExpID VCode::new_vmx_indirect(VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Indirect);
        auto& args = exp_ref.args.i_indirect;
        args.x = next;
        return exp_id;
    }
    VmExpID VCode::new_vmx_assign_local(size_t n, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::AssignLocal);
        auto& args = exp_ref.args.i_assign;
        args.n = n;
        args.x = next;
        return exp_id;
    }
    VmExpID VCode::new_vmx_assign_free(size_t n, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::AssignFree);
        auto& args = exp_ref.args.i_assign;
        args.n = n;
        args.x = next;
        return exp_id;
    }
    VmExpID VCode::new_vmx_assign_global(size_t gn, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::AssignGlobal);
        auto& args = exp_ref.args.i_assign;
        args.n = gn;
        args.x = next;
        return exp_id;
    }
    VmExpID VCode::new_vmx_shift(ssize_t n, ssize_t m, VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Shift);
        auto& args = exp_ref.args.i_shift;
        args.n = n;
        args.m = m;
        args.x = x;
        return exp_id;
    }
    VmExpID VCode::new_vmx_pinvoke(ssize_t arg_count, size_t platform_proc_idx, VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::PInvoke);
        auto& args = exp_ref.args.i_pinvoke;
        args.n = arg_count;
        args.proc_id = platform_proc_idx;
        args.x = x;
        return exp_id;
    }

    /// Dump
    //
    void VCode::dump(std::ostream& out) const {
        out << "--- ALL_EXPS ---" << std::endl;
        print_all_exps(out);
        out << "--- ALL_FILES ---" << std::endl;
        print_all_files(out);
    }
    void VCode::print_all_exps(std::ostream& out) const {
        size_t pad_w = static_cast<size_t>(std::ceil(std::log(1+m_exps.size()) / std::log(10)));
        for (size_t index = 0; index < m_exps.size(); index++) {
            out << "  [";
            out << std::setfill('0') << std::setw(pad_w) << index;
            out << "] ";

            print_one_exp(index, out);
            
            out << std::endl;
        }
    }
    void VCode::print_one_exp(VmExpID exp_id, std::ostream& out) const {
        auto const& exp = m_exps[exp_id];
        out << "(";
        switch (exp.kind) {
            case VmExpKind::Halt: {
                out << "halt";
            } break;
            case VmExpKind::ReferLocal: {
                out << "refer-local "
                    << "#:n " << exp.args.i_refer.n << ' '
                    << "#:x " << exp.args.i_refer.x;
            } break;
            case VmExpKind::ReferFree: {
                out << "refer-free "
                    << "#:n " << exp.args.i_refer.n << ' '
                    << "#:x " << exp.args.i_refer.x;
            } break;
            case VmExpKind::ReferGlobal: {
                out << "refer-global "
                    << "#:n " << exp.args.i_refer.n << ' '
                    << "#:x " << exp.args.i_refer.x;
            } break;
            case VmExpKind::AssignLocal: {
                out << "assign-local "
                    << "#:n " << exp.args.i_assign.n << ' '
                    << "#:x " << exp.args.i_assign.x;
            } break;
            case VmExpKind::AssignFree: {
                out << "assign-free "
                    << "#:n " << exp.args.i_assign.n << ' '
                    << "#:x " << exp.args.i_assign.x;
            } break;
            case VmExpKind::AssignGlobal: {
                out << "assign-global "
                    << "#:n " << exp.args.i_assign.n << ' '
                    << "#:x " << exp.args.i_assign.x;
            } break;
            case VmExpKind::Constant: {
                out << "constant "
                    << "#:obj " << exp.args.i_constant.obj << ' '
                    << "#:x " << exp.args.i_constant.x;
            } break;
            case VmExpKind::Close: {
                out << "close "
                    << "#:body " << exp.args.i_close.body << ' '
                    << "#:x " << exp.args.i_close.x;
            } break;
            case VmExpKind::Test: {
                out << "test "
                    << "#:vmx " << exp.args.i_test.next_if_t << ' '
                    << "#:vmx " << exp.args.i_test.next_if_f;
            } break;
            case VmExpKind::Conti: {
                out << "conti ";
                out << "#:x " << exp.args.i_conti.x;
            } break;
            case VmExpKind::Nuate: {
                out << "nuate "
                    << "#:stack " << exp.args.i_nuate.stack << ' '
                    << "#:x " << exp.args.i_nuate.x;
            } break;
            case VmExpKind::Frame: {
                out << "frame "
                    << "#:fn-body-x " << exp.args.i_frame.fn_body_x << ' '
                    << "#:post-ret-x " << exp.args.i_frame.post_ret_x;
            } break;
            case VmExpKind::Argument: {
                out << "argument "
                    << "#:vmx " << exp.args.i_argument.x;
            } break;
            case VmExpKind::Apply: {
                out << "apply";
            } break;
            case VmExpKind::Return: {
                out << "return";
            } break;
            case VmExpKind::Define: {
                out << "define ";
                print_obj(exp.args.i_define.var, out);
                out << " "
                    << "#:vmx " << exp.args.i_define.next;
            } break;
            case VmExpKind::Indirect: {
                out << "indirect #:x" << exp.args.i_indirect.x;
            } break;
            case VmExpKind::Box: {
                out << "box #:n " << exp.args.i_box.n << " #:x " << exp.args.i_box.x;
            } break;
            case VmExpKind::Shift: {
                out << "box #:m " << exp.args.i_shift.m << " #:n " << exp.args.i_box.n << " #:x " << exp.args.i_box.x;
            } break;
            case VmExpKind::PInvoke: {
                out << "p/invoke #:n " << exp.args.i_pinvoke.n << " #:proc_idx " << exp.args.i_pinvoke.proc_id;
            } break;
        }
        out << ")";
    }
    void VCode::print_all_files(std::ostream& out) const {
        for (size_t i = 0; i < m_subrs.size(); i++) {
            out << "  " "- file #:" << 1+i << std::endl;
            VSubr const& f = *(m_subrs.cbegin() + i);

            for (size_t j = 0; j < f.line_code_objs.size(); j++) {
                OBJECT line_code_obj = f.line_code_objs[j];
                VmProgram program = f.line_programs[j];

                out << "    " "  > ";
                print_obj(line_code_obj, out);
                out << std::endl;
                out << "    " " => " << "(#:vmx" << program.s << " #:vmx" << program.t << ")";
                out << std::endl;
            }
        }
    }

}   // namespace ss
