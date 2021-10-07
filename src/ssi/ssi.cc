#include <sstream>
#include <fstream>

#include "parser.hh"
#include "feedback.hh"
#include "printing.hh"

void interpret_file(std::string file_path) {
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

    Parser* p = create_parser(f, std::move(file_path));
    
    // interpreting this file:
    for (;;) {
        Object* line_code_obj = parse_next_line(p);
        if (line_code_obj == nullptr) {
            break;
        } else {
            // printing the line back:
            std::cout << "  > ";
            print_obj(line_code_obj, std::cout);
            std::cout << std::endl;

            // todo: evaluate this line:
        }
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
        interpret_file(argv[1]);
        return 0;
    }

}
