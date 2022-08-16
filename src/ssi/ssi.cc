#include <iostream>
#include <sstream>
#include <fstream>
#include <chrono>

#include "ss-core/allocator.hh"
#include "ss-core/feedback.hh"
#include "ss-core/gc.hh"
#include "ss-core/cli.hh"
#include "ss-core/parser.hh"
#include "ss-core/printing.hh"
#include "ss-core/vm.hh"
#include "ss-core/compiler.hh"
#include "ss-core/library.hh"

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
            if (raw.pos.size() != 1) {
                std::stringstream ss;
                ss << "Expected exactly 1 positional argument, denoting the entry-point filepath: got " << raw.pos.size();
                error(ss.str());
                throw SsiError();
            }

            // pos args
            //
            
            // entry_point_path
            res.entry_point_path = raw.pos[0];

            // arity-1 (ar1) args
            //

            // snail_root:
            auto const snail_root_default = "./snail-venv";
            auto snail_root_it = raw.ar1.find("snail-root");
            res.snail_root = (
                snail_root_it == raw.ar1.end() ? 
                std::string{snail_root_default} : 
                snail_root_it->second
            );

            // heap_gib:
            auto const heap_size_in_bytes_default = GIBIBYTES(2);
            auto heap_gib_it = raw.ar1.find("heap-gib");
            res.heap_size_in_bytes = (
                heap_gib_it == raw.ar1.end() ? 
                heap_size_in_bytes_default :
                GIBIBYTES(strtoull(heap_gib_it->second.c_str(), nullptr, 10))
            );

            // ar0
            //

            res.help = (raw.ar0.find("help") != raw.ar0.end());
            res.debug = (raw.ar0.find("debug") != raw.ar0.end());

            // arN: none
            //
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
        std::vector<OBJECT> line_code_obj_array;
        {
            auto start = std::chrono::steady_clock::now();
            Parser* p = create_parser(f, file_path, vm_gc_tfe(vm));
            line_code_obj_array = parse_all_subsequent_line_datums(p);
            auto end = std::chrono::steady_clock::now();
            auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);

#if CONFIG_DEBUG_MODE
            {
                std::stringstream ss;
                ss << "parsing took " << duration;
                info(ss.str());
            }
#endif

#if CONFIG_DEBUG_MODE
            {
                std::stringstream ss;
                ss << "parsed '" << file_path << "'" << std::endl;
                for (size_t i = 0; i < line_code_obj_array.size(); i++) {
                    auto o = line_code_obj_array[i];
                    ss << "- " << o;
                    if (i+1 < line_code_obj_array.size()) {
                        ss << std::endl;
                    }
                }
                info(ss.str());
            }
#endif
        }

        // compiling the program into VM representation:
        // c.f. §3.4.2 (Translation) on p.56 (pos 66/190)
        {
            auto start = std::chrono::steady_clock::now();
            ss::Compiler& compiler = *vm_compiler(vm);
            ss::VCode* code = compiler.code();
            try {
                VSubr subr = compiler.compile_subr(file_path, std::move(line_code_obj_array));
                code->append_subroutine(file_path, std::move(subr));
            } catch (SsiError const& ssi_error) {
                return;
            }
            auto end = std::chrono::steady_clock::now();
            auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);

#if CONFIG_DEBUG_MODE
            std::stringstream ss;
            ss << "compile and lib-loading took " << duration;
            info(ss.str());
#endif
        }
        
        // Executing:
        {
            auto start = std::chrono::steady_clock::now();
            try {
                bool print_each_line = false;
                sync_execute_vm(vm, print_each_line);
            } catch (SsiError const& ssi_error) {
                return;
            }
            auto end = std::chrono::steady_clock::now();
            auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
            
#if CONFIG_DEBUG_MODE
            std::stringstream ss;
            ss << "runtime took " << duration;
            info(ss.str());
#endif
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
    // TODO: detect if 'snail-venv' directory exists in CWD: if so, elide `-snail-venv` arg.
    ss::SsiArgs args = ss::parse_cli_args(argc, argv);
    if (args.help) {
        ss::info("TODO: printing 'help' and exiting");
        return 0;
    }
    if (args.debug) {
        std::cerr 
            << "INFO: using command-line args:" << std::endl
            << argv[0] << std::endl
            << "    " << args.entry_point_path << std::endl
            << "    -snail-root " << args.snail_root << std::endl
            << "    -heap-gib " << args.heap_size_in_bytes / ss::GIBIBYTES(1) << std::endl;
        if (args.debug) {
            std::cerr
                << "    -debug" << std::endl;
        }
        if (args.help) {
            std::cerr
                << "    -help" << std::endl;
        }
    }

    // Initializing the GC, may be shared among multiple VMs
    size_t constexpr max_heap_size_in_bytes = ss::GIBIBYTES(4);
    size_t constexpr max_heap_size_in_pages = max_heap_size_in_bytes >> CONFIG_TCMALLOC_PAGE_SHIFT;
    ss::Gc gc {
        reinterpret_cast<ss::APtr>(calloc(max_heap_size_in_pages, ss::gc::PAGE_SIZE_IN_BYTES)), 
        max_heap_size_in_bytes
    };

    // Initializing the central library repository at the snail-root specified:
    bool clr_init_ok = ss::CentralLibraryRepository::ensure_init(args.snail_root);
    if (!clr_init_ok) {
        std::stringstream error_ss;
        error_ss
            << "Failed to initialize the Central Library Repository (CLR)";
        ss::error(error_ss.str());
        return 2;
    }

    // Instantiating, programming, and running a VM:
    // TODO: switch to JIT
    ss::VirtualMachine* vm = ss::create_vm(&gc);
    ss::interpret_file(vm, argv[1]);

    // all OK
    return 0;
}
