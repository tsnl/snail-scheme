#include <sstream>
#include <fstream>
#include <iostream>

#include "parser.hh"
#include "feedback.hh"
#include "printing.hh"
#include "vm.hh"

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
    std::vector<Object const*> line_code_obj_array = parse_all_subsequent_lines(p);
    
    for (auto line_code_obj: line_code_obj_array) {
        std::cout << "  > ";
        print_obj(line_code_obj, std::cout);
        std::cout << std::endl;
    }

    // compiling the program into VM representation:
    // c.f. §3.4.2 (Translation) on p.56 (pos 66/190)
    add_file_to_vm(vm, file_path, std::move(line_code_obj_array));

    // Executing:
    {
        sync_execute_vm(vm, true);
    }

    // Dumping:
    {
        info("Successfully generated VM bytecode for file '" + file_path + "'");
        info("Begin Dump:");
        dump_vm(vm, std::cout);
        info("End Dump");
    }
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
        VirtualMachine* vm = create_vm();
        interpret_file(vm, argv[1]);
        return 0;
    }
}
