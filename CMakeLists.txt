cmake_minimum_required(VERSION 3.0.0)
project(SnailScheme VERSION 0.0.0)

#
# Google Test
#

include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/FetchGoogleTest.cmake)
include(GoogleTest)

#
# Global Config
#

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/inc/
    ${CMAKE_CURRENT_SOURCE_DIR}/tcmalloc/
)

set(CMAKE_CXX_STANDARD 20)
if (WIN32)
    # set stuff for windows
elseif(APPLE)
    set(CMAKE_CXX_FLAGS "-glldb")
else()
    # TODO: set linux stuff
endif()
include_directories(src)

#
# Generating Source
#

configure_file(
    ${CMAKE_SOURCE_DIR}/inc/config/config.hh.in
    ${CMAKE_SOURCE_DIR}/inc/config/config.hh
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
    ${CMAKE_CURRENT_SOURCE_DIR}/src/snail-scheme/gc.cc
)
# target_link_libraries(snail-scheme BDWgc::gc)

add_executable(
    ssi
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ssi/ssi.cc
)
target_link_libraries(ssi snail-scheme)

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
