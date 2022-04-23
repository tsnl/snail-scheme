cmake_minimum_required(VERSION 3.0.0)
project(SnailScheme VERSION 0.0.0)

##
# Required Config
#

set(CLANG_PATH "" CACHE FILEPATH "Path to 'clang' executable")
if ("" STREQUAL "${CLANG_PATH}")
    # trying to recover by setting a default path
    if (WIN32)
        set(DEFAULT_PATH "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/Llvm/bin/clang.exe")
    else()
        set(DEFAULT_PATH "$--inexistent-phony--$")
    endif()
    if (EXISTS ${DEFAULT_PATH})
        set(CLANG_PATH ${DEFAULT_PATH} CACHE FILEPATH "Path to 'clang' executable" FORCE)
    else()
        message(
            FATAL_ERROR
            "Please set 'CLANG_PATH' configuration variable.\n"
            "auto-detected `clang` at: ${DEFAULT_LLVM_PATH}"
        )
    endif()
endif()

#
# Google Test
#

include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/FetchGoogleTest.cmake)
include(GoogleTest)
include(ExternalProject)

#
# Global Config
#

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/inc/
)

set(CMAKE_CXX_STANDARD 20)

if (WIN32)
    # set stuff for windows
elseif(APPLE)
    
else()
    # set linux stuff
endif()
include_directories(src)

#
# Generating Source
#

configure_file(
    ${CMAKE_SOURCE_DIR}/inc/ss-config/config.hh.in
    ${CMAKE_SOURCE_DIR}/inc/ss-config/config.hh
)
configure_file(
    ${CMAKE_SOURCE_DIR}/src/ss-stdlib/Makefile.in
    ${CMAKE_SOURCE_DIR}/src/ss-stdlib/Makefile
)

#
# Configuring Targets
#

add_library(
    snail-scheme
    
    # ${CMAKE_CURRENT_SOURCE_DIR}/inc/snail-scheme/core.hh
    # ${CMAKE_CURRENT_SOURCE_DIR}/inc/snail-scheme/feedback.hh
    # ${CMAKE_CURRENT_SOURCE_DIR}/inc/snail-scheme/intern.hh
    # ${CMAKE_CURRENT_SOURCE_DIR}/inc/snail-scheme/object.hh
    # ${CMAKE_CURRENT_SOURCE_DIR}/inc/snail-scheme/parser.hh
    # ${CMAKE_CURRENT_SOURCE_DIR}/inc/snail-scheme/printing.hh
    # ${CMAKE_CURRENT_SOURCE_DIR}/inc/snail-scheme/vm.hh
    # ${CMAKE_CURRENT_SOURCE_DIR}/inc/snail-scheme/heap.hh

    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/feedback.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/intern.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/object.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/parser.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/printing.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/vm.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/reactor.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/memory.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/std.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/smt.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/gc.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/mir.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/compiler.cc
)

# see: https://cmake.org/cmake/help/v2.8.11/cmake.html#module:ExternalProject
ExternalProject_Add(
    ss-stdlib
    DEPENDS snail-scheme
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-stdlib
    CONFIGURE_COMMAND
        ""
    BUILD_COMMAND
        ${CMAKE_COMMAND} -E env
            make -C <SOURCE_DIR>
    BUILD_IN_SOURCE TRUE
    INSTALL_COMMAND
        echo "TODO: install command"
)

add_executable(
    ssi
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ssi/ssi.cc
)
target_link_libraries(ssi snail-scheme)
add_dependencies(ssi ss-stdlib)

add_executable(
    ss-tests
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/TestTest.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/TestObject1.cc
)
target_link_libraries(
    ss-tests
    gtest_main
)
gtest_discover_tests(ss-tests)
