#include <sstream>
#include <fstream>
#include <iostream>

#include "parser.hh"
#include "feedback.hh"
#include "printing.hh"
#include "object-v2.hh"
#include "vm.hh"

void test_obj_v2() {
    print_obj2(c_integer(42), std::cout);
    print_obj2(c_integer(21), std::cout);
    print_obj2(c_integer(-1), std::cout);
    print_obj2(c_integer(0), std::cout);
    print_obj2(c_integer(-2041231241241), std::cout);
    print_obj2(c_flonum(500.0), std::cout);

    std::cout 
        << "Done."
        << std::endl;
}

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
    Parser* p = create_parser(f, file_path);
    std::vector<Object*> line_code_obj_array = parse_all_subsequent_lines(p);
    
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
        sync_execute_vm(vm);
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
    // debug only:
    bool just_run_v2_test = true;
    if (just_run_v2_test) {
        test_obj_v2();
        return 0;
    }

    // main routine:
    if (argc != 2) {
        std::stringstream error_ss;
        error_ss
            << "Usage:\t" << argv[0] << " <source-file-path>" << std::endl
            << "Invalid usage: expected 2 arguments, received " << argc << "." << std::endl;
        error(error_ss.str());
        return 1;
    } else {
        VirtualMachine* vm = create_vm();
        // interpret_file(vm, argv[1]);
        return 0;
    }
}
