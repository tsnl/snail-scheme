#pragma once

#include <string>
#include <vector>

#include "object.hh"

class Parser;

Parser* create_parser(std::string file_path);
void dispose_parser(Parser* p);
Object* parse_next_line(Parser* p);
std::vector<Object*> parse_all_subsequent_lines(Parser* p);
