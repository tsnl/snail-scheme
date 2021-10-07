#pragma once

#include <string>
#include <vector>
#include <istream>

#include "object.hh"

class Parser;

// creates a parser using the provided input-stream reference.
// WARNING: if the `std::istream&` goes out of scope, we will segfault.
Parser* create_parser(std::istream& input_stream, std::string input_desc);

void dispose_parser(Parser* p);
Object* parse_next_line(Parser* p);
std::vector<Object*> parse_all_subsequent_lines(Parser* p);

void run_lexer_test_and_dispose_parser(Parser* p);