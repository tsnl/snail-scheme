#include <sstream>

#include "parser.hh"
#include "feedback.hh"

void interpret_file(std::string file_path) {
    Parser* p = create_parser(file_path);
    
    // DEBUG only:
    parse_all_subsequent_lines(p);
}

int main(int argc, char const* argv[]) {
    if (argc != 2) {
        std::stringstream more_ss;
        more_ss << "Usage:\t" << argv[0] << " <source-file-path>";
        error("Invalid usage: expected 2 arguments.");
        more(more_ss.str());
    }

    interpret_file(argv[1]);
    
    return 0;
}
