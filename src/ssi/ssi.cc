#include <iostream>
#include <sstream>
#include <fstream>

#include "ss-core/allocator.hh"
#include "ss-core/feedback.hh"
#include "ss-jit/parser.hh"
#include "ss-jit/printing.hh"
#include "ss-jit/vm.hh"
#include "ss-jit/compiler.hh"
#include "ss-core/gc.hh"

namespace ss {

    void interpret_file(VirtualMachine* vm, std::string file_path) {
        // opening the file:
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
        ss::Compiler& compiler = *vm_compiler(vm);;
        ss::VCode& code = compiler.code();
        VSubr subr = compiler.compile_subroutine(file_path, std::move(line_code_obj_array));
        code.append_subroutine(file_path, std::move(subr));
        
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
    // TODO: switch to more flexible command-line options parser with...
    // - heap size in bytes
    if (argc != 2) {
        std::stringstream error_ss;
        error_ss
            << "Usage:\t" << argv[0] << " <source-file-path>" << std::endl
            << "Invalid usage: expected 2 arguments, received " << argc << "." << std::endl;
        ss::error(error_ss.str());
        return 1;
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
