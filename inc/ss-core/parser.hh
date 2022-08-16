#pragma once

#include <string>
#include <vector>
#include <istream>
#include <optional>

#include "ss-core/object.hh"
#include "ss-core/gc.hh"

// Core 'Parser' API: useful for parsing multiple files:
namespace ss {

    class Parser;

    // creates a parser using the provided input-stream reference.
    // WARNING: if the `std::istream&` goes out of scope, we will segfault.
    Parser* create_parser(std::istream& input_stream, std::string input_desc, GcThreadFrontEnd* gc_tfe);
    void dispose_parser(Parser* p);

    // (deprecated) extract one line datum from the stream:
    std::optional<OBJECT> parse_next_line_datum(Parser* p);

    // (deprecated) extract as many line datums as possible from the stream:
    std::vector<OBJECT> parse_all_subsequent_line_datums(Parser* p);

    // extract one line's syntax object from the stream:
    std::optional<OBJECT> parse_next_line(Parser* p);

    // extract as many lines' syntax objects as possible from the stream:
    std::vector<OBJECT> parse_all_subsequent_lines(Parser* p);

}   // namespace ss

// Debug:
namespace ss {
    void run_lexer_test_and_dispose_parser(Parser* p);
}