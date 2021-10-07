#include "feedback.hh"

void help_fb_print(char const* prefix, std::string msg) {
    std::cout << prefix;
    for (char const c: msg) {
        std::cout << c;
        if (c == '\n') {
            std::cout << "       ";
        }
    }
    std::cout << std::endl;
}
void error(std::string msg)     { help_fb_print("ERROR: ", std::move(msg)); }
void warning(std::string msg)   { help_fb_print("WARN:  ", std::move(msg)); }
void info(std::string msg)      { help_fb_print("INFO:  ", std::move(msg)); }
void more(std::string msg)      { help_fb_print("       ", std::move(msg)); }
