#include "intern.hh"
#include <map>
#include <vector>

static std::map<IntStr, std::string> s_intern_map;
static std::vector<std::string>      s_string_map;

IntStr intern(std::string s) {
    IntStr new_int_str = s_string_map.size();
    auto insert_rec = s_intern_map.insert({new_int_str, s});
    if (insert_rec.second) {
        // insertion successful => this is a new entry in the intern map => update `s_string_map`
        s_string_map.push_back(s);
        return new_int_str;
    } else {
        // insertion failed => an old entry exists => query existing interned string ID
        return insert_rec.first->first;
    }
}

std::string const& interned_string(IntStr int_str) {
    return s_string_map[int_str];
}