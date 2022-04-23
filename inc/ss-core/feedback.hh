#pragma once

#include <iostream>
#include <string>
#include <exception>

namespace ss {

    class SsiError: std::exception {
    public:
        inline SsiError() {
            std::cout << "FATAL-ERROR: see above error messages." << std::endl;
        }
    };

    void error(std::string msg);
    void warning(std::string msg);
    void info(std::string msg);
    void more(std::string msg);

}   // namespace ss