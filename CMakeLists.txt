cmake_minimum_required(VERSION 3.0.0)
project(SnailScheme VERSION 0.0.0)

set(CMAKE_CXX_STANDARD 20)
if (WIN32)
    # set stuff for windows
elseif(APPLE)
    set(CMAKE_CXX_FLAGS "-glldb")
else()
    # TODO: set linux stuff
endif()
include_directories(src)

configure_file(
    src/config/config.hh.in
    ${CMAKE_SOURCE_DIR}/src/config/config.hh
)

add_executable(
    ssi
    src/ssi/ssi.cc
    src/ssi/core.hh
    src/ssi/feedback.cc
    src/ssi/feedback.hh
    src/ssi/intern.cc
    src/ssi/intern.hh
    src/ssi/object.cc
    src/ssi/object.hh
    src/ssi/parser.cc
    src/ssi/parser.hh
    src/ssi/printing.cc
    src/ssi/printing.hh
    src/ssi/vm.cc
    src/ssi/vm.hh
    src/ssi/heap.hh
)
