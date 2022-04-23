#include <sstream>
#include <fstream>
#include <iostream>

#include "snail-scheme/allocator.hh"
#include "snail-scheme/parser.hh"
#include "snail-scheme/feedback.hh"
#include "snail-scheme/printing.hh"
#include "snail-scheme/vm.hh"
#include "snail-scheme/reactor.hh"
#include "snail-scheme/gc.hh"

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
    add_file_to_vm(vm, file_path, std::move(line_code_obj_array));

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

int main(int argc, char const* argv[]) {
    if (argc != 2) {
        std::stringstream error_ss;
        error_ss
            << "Usage:\t" << argv[0] << " <source-file-path>" << std::endl
            << "Invalid usage: expected 2 arguments, received " << argc << "." << std::endl;
        error(error_ss.str());
        return 1;
    } else {
        size_t const max_heap_size_in_bytes = GIGABYTES(4);
        size_t const num_pages = max_heap_size_in_bytes >> CONFIG_TCMALLOC_PAGE_SHIFT;
        Gc gc {
            reinterpret_cast<APtr>(calloc(num_pages, gc::PAGE_SIZE_IN_BYTES)), 
            max_heap_size_in_bytes
        };
        std::cerr << "INFO: successfully instantiated GC." << std::endl;
        VirtualMachine* vm = create_vm(&gc);
        interpret_file(vm, argv[1]);
        return 0;
    }
}
