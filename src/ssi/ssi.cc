#include <iostream>
#include <sstream>
#include <fstream>

#include "ss-core/allocator.hh"
#include "ss-core/feedback.hh"
#include "ss-core/gc.hh"
#include "ss-core/cli.hh"
#include "ss-jit/parser.hh"
#include "ss-jit/printing.hh"
#include "ss-jit/vm.hh"
#include "ss-jit/compiler.hh"
#include "ss-jit/libs.hh"

namespace ss {

    struct SsiArgs {
        std::string entry_point_path;
        std::string snail_root;
        size_t heap_size_in_bytes;
        bool debug;
        bool help;
    };

    SsiArgs parse_cli_args(int argc, char const* argv[]) {
        CliArgsParser parser;
        parser.add_ar0_option_rule("help");
        parser.add_ar0_option_rule("debug");
        parser.add_ar1_option_rule("heap-gib");
        parser.add_ar1_option_rule("snail-root");
        CliArgs raw = parser.parse(argc, argv);
        
        SsiArgs res; {
            // checking:
            auto snail_root_it = raw.ar1.find("snail-root");
            auto heap_gib_it = raw.ar1.find("heap-gib");
            if (snail_root_it == raw.ar1.end()) {
                error("Expected mandatory optional parameter '-snail-root'");
                throw SsiError();
            }
            if (raw.pos.size() != 1) {
                error("Expected exactly 1 positional argument, denoting the entry-point filepath");
                throw SsiError();
            }

            // pos:
            res.entry_point_path = raw.pos[0];

            // ar1
            res.snail_root = snail_root_it->second;
            res.heap_size_in_bytes = (
                heap_gib_it == raw.ar1.end() ? 
                GIBIBYTES(2) :      // default heap size: 2GiB
                GIBIBYTES(strtoull(heap_gib_it->second.c_str(), nullptr, 10))
            );

            // ar0
            res.help = (raw.ar0.find("help") != raw.ar0.end());
            res.debug = (raw.ar0.find("debug") != raw.ar0.end());
        }
        return std::move(res);
    }

    void interpret_file(VirtualMachine* vm, std::string file_path) {
        // Opening the file:
        std::ifstream f;
        f.open(file_path);
        if (!f.is_open()) {
            std::stringstream error_ss;
            error_ss
                << "Failed to load file \"" << file_path << "\" to interpret." << std::endl 
                << "Does it exist? Is it readable?";
            error(error_ss.str());
            return;
        }

        // parsing all lines into a vector:
        Parser* p = create_parser(f, file_path, vm_gc_tfe(vm));
        std::vector<OBJECT> line_code_obj_array = parse_all_subsequent_lines(p);
        
        // todo: load into a module before compilation
        //  - cf https://docs.racket-lang.org/guide/Module_Syntax.html?q=modules#%28part._module-syntax%29
        //  - first, implement the 'module' syntax
        //  - later, can implement '#lang' syntax (see below)

        // todo: languages by modifying reader level
        //  - specifying a '#lang <language>' line can delegate to different parsers
        //  - cf https://docs.racket-lang.org/guide/languages.html?q=modules

        // compiling the program into VM representation:
        // c.f. §3.4.2 (Translation) on p.56 (pos 66/190)
        ss::Compiler& compiler = *vm_compiler(vm);
        ss::VCode* code = compiler.code();
        VSubr subr = compiler.compile_subroutine(file_path, std::move(line_code_obj_array));
        code->append_subroutine(file_path, std::move(subr));
        
        // Executing:
        {
            bool print_each_line = true;
            sync_execute_vm(vm, print_each_line);
        }

        // Dumping:
    #if CONFIG_DUMP_VM_STATE_AFTER_EXECUTION
        {
            info("Begin Dump:");
            dump_vm(vm, std::cout);
            info("End Dump");
        }
    #endif
    }

}   // namespace ss

int main(int argc, char const* argv[]) {
    // Parsing command-line arguments:
    ss::SsiArgs args = ss::parse_cli_args(argc, argv);
    if (args.help) {
        ss::info("TODO: printing 'help' and exiting");
        return 0;
    }
    if (true) {
        std::cerr 
            << "TODO: using command-line args:" << std::endl
            << argv[0] << std::endl
            << "    " << args.entry_point_path << std::endl
            << "    -snail-root " << args.snail_root << std::endl
            << "    -heap-gib " << args.heap_size_in_bytes / ss::GIBIBYTES(1) << std::endl;
    }
    if (args.debug) {
        std::cerr
            << "    -debug" << std::endl;
    }
    if (args.help) {
        std::cerr
            << "    -help" << std::endl;
    }
    return 0;

    // Initializing the central library repository:
    bool clr_init_ok = ss::CentralLibraryRepository::ensure_init(argv[0]);
    if (!clr_init_ok) {
        std::stringstream error_ss;
        error_ss
            << "Failed to initialize the Central Library Repository (CLR)";
        ss::error(error_ss.str());
        return 2;
    }

    // Instantiating, programming, and running a VM:
    // TODO: switch to JIT
    size_t constexpr max_heap_size_in_bytes = ss::GIBIBYTES(4);
    size_t constexpr max_heap_size_in_pages = max_heap_size_in_bytes >> CONFIG_TCMALLOC_PAGE_SHIFT;
    ss::Gc gc {
        reinterpret_cast<ss::APtr>(calloc(max_heap_size_in_pages, ss::gc::PAGE_SIZE_IN_BYTES)), 
        max_heap_size_in_bytes
    };
    ss::VirtualMachine* vm = ss::create_vm(&gc);
    ss::interpret_file(vm, argv[1]);

    // all OK
    return 0;
}
