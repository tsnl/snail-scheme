#include "snail-scheme/intern.hh"
#include <map>
#include <vector>

static std::map<std::string, IntStr> s_intern_map;
static std::vector<std::string>      s_string_map;

IntStr intern(std::string s) {
    IntStr new_int_str = s_string_map.size();
    auto insert_rec = s_intern_map.insert({s, new_int_str});
    if (insert_rec.second) {
        // insertion successful => this is a new entry in the intern map => update `s_string_map`
        s_string_map.push_back(s);
        return new_int_str;
    } else {
        // insertion failed => an old entry exists => query existing interned string ID
        return insert_rec.first->second;
    }
}

std::string const& interned_string(IntStr int_str) {
    return s_string_map[int_str];
}