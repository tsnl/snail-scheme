#include "ss-jit/vrom.hh"
#include <iomanip>
#include <sstream>

#include "ss-jit/printing.hh"


namespace ss {

    /// VRom:
    //
    VRom::VRom(size_t file_count)
    :   m_exps(), 
        m_files()
    {
        m_exps.reserve(4096);
        m_files.reserve(file_count);
    }
    void VRom::add_script(std::string const& file_name, VScript&& script) {
        assert(script.line_code_objs.size() == script.line_programs.size());
        if (!script.line_programs.empty()) {
            // storing the input lines and the programs on this VM:
            m_files.push_back(std::move(script));
        } else {
            warning(std::string("VM: Input file `") + file_name + "` is empty.");
        }
    }
    VRom::VRom(VRom&& other) noexcept
    :   m_exps(std::move(other.m_exps)),
        m_files(std::move(other.m_files)) 
    {}

    void VRom::flash(VRom&& other) {
        VRom::~VRom();
        new(this) VRom(std::move(other));
    }

    /// Creating VM Expressions:
    //
    std::pair<VmExpID, VmExp&> VRom::help_new_vmx(VmExpKind kind) {
        VmExpID exp_id = m_exps.size();
        VmExp& exp_ref = m_exps.emplace_back(kind);
        return {exp_id, exp_ref};
    }
    VmExpID VRom::new_vmx_halt() {
        return help_new_vmx(VmExpKind::Halt).first;
    }
    VmExpID VRom::new_vmx_refer(OBJECT var, VmExpID next) {
        assert(var.is_pair() && car(var).is_integer() && cdr(var).is_integer());
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Refer);
        auto& args = exp_ref.args.i_refer;
        args.var = var;
        args.x = next;
        return exp_id;
    }
    VmExpID VRom::new_vmx_constant(OBJECT constant, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Constant);
        auto& args = exp_ref.args.i_constant;
        args.constant = constant;
        args.x = next;
        return exp_id;
    }
    VmExpID VRom::new_vmx_close(OBJECT vars, VmExpID body, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Close);
        auto& args = exp_ref.args.i_close;
        args.body = body;
        args.x = next;
        return exp_id;
    }
    VmExpID VRom::new_vmx_test(VmExpID next_if_t, VmExpID next_if_f) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Test);
        auto& args = exp_ref.args.i_test;
        args.next_if_t = next_if_t;
        args.next_if_f = next_if_f;
        return exp_id;
    }
    VmExpID VRom::new_vmx_assign(OBJECT var, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Assign);
        auto& args = exp_ref.args.i_assign;
        args.var = var;
        args.x = next;
        return exp_id;
    }
    VmExpID VRom::new_vmx_conti(VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Conti);
        auto& args = exp_ref.args.i_conti;
        args.x = x;
        return exp_id;
    }
    VmExpID VRom::new_vmx_nuate(OBJECT stack, OBJECT var) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Nuate);
        auto& args = exp_ref.args.i_nuate;
        args.s = stack;
        args.var = var;
        return exp_id;
    }
    VmExpID VRom::new_vmx_frame(VmExpID x, VmExpID ret) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Frame);
        auto& args = exp_ref.args.i_frame;
        args.x = x;
        args.ret = ret;
        return exp_id;
    }
    VmExpID VRom::new_vmx_argument(VmExpID x) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Argument);
        auto& args = exp_ref.args.i_argument;
        args.x = x;
        return exp_id;
    }
    VmExpID VRom::new_vmx_apply() {
        return help_new_vmx(VmExpKind::Apply).first;
    }
    VmExpID VRom::new_vmx_return() {
        return help_new_vmx(VmExpKind::Return).first;
    }
    VmExpID VRom::new_vmx_define(OBJECT var, VmExpID next) {
        auto [exp_id, exp_ref] = help_new_vmx(VmExpKind::Define);
        auto& args = exp_ref.args.i_define;
        args.var = var;
        args.next = next;
        return exp_id;
    }

    /// Dump
    //
    void VRom::dump(std::ostream& out) const {
        out << "--- ALL_EXPS ---" << std::endl;
        print_all_exps(out);
        out << "--- ALL_FILES ---" << std::endl;
        print_all_files(out);
    }
    void VRom::print_all_exps(std::ostream& out) const {
        size_t pad_w = static_cast<size_t>(std::ceil(std::log(1+m_exps.size()) / std::log(10)));
        for (size_t index = 0; index < m_exps.size(); index++) {
            out << "  [";
            out << std::setfill('0') << std::setw(pad_w) << index;
            out << "] ";

            print_one_exp(index, out);
            
            out << std::endl;
        }
    }
    void VRom::print_one_exp(VmExpID exp_id, std::ostream& out) const {
        auto const& exp = m_exps[exp_id];
        out << "(";
        switch (exp.kind) {
            case VmExpKind::Halt: {
                out << "halt";
            } break;
            case VmExpKind::Refer: {
                out << "refer ";
                print_obj(exp.args.i_refer.var, out);
                out << ' ';
                out << "#:vmx " << exp.args.i_refer.x;
            } break;
            case VmExpKind::Constant: {
                out << "constant ";
                print_obj(exp.args.i_constant.constant, out);
                out << ' ';
                out << "#:vmx " << exp.args.i_constant.x;
            } break;
            case VmExpKind::Close: {
                out << "close ";
                print_obj(exp.args.i_refer.var, out);
                out << ' ';
                out << "#:vmx " << exp.args.i_refer.x;
            } break;
            case VmExpKind::Test: {
                out << "test "
                    << "#:vmx " << exp.args.i_test.next_if_t << ' '
                    << "#:vmx " << exp.args.i_test.next_if_f;
            } break;
            case VmExpKind::Assign: {
                out << "assign ";
                print_obj(exp.args.i_assign.var, out);
                out << ' ';
                out << "#:vmx " << exp.args.i_assign.x;
            } break;
            case VmExpKind::Conti: {
                out << "conti ";
                out << "#:vmx " << exp.args.i_conti.x;
            } break;
            case VmExpKind::Nuate: {
                out << "nuate ";
                print_obj(exp.args.i_nuate.var, out);
                out << ' '
                    << "#:vmx " << exp.args.i_nuate.s;
            } break;
            case VmExpKind::Frame: {
                out << "frame "
                    << "#:vmx " << exp.args.i_frame.x << ' '
                    << "#:vmx " << exp.args.i_frame.ret;
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
        }
        out << ")";
    }
    void VRom::print_all_files(std::ostream& out) const {
        for (size_t i = 0; i < m_files.size(); i++) {
            out << "  " "- file #:" << 1+i << std::endl;
            VScript const& f = *(m_files.cbegin() + i);

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
