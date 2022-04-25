cmake_minimum_required(VERSION 3.7)
project(SnailScheme VERSION 0.0.0)

## Cache config
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

## Dependency: Google Test
#

include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/FetchGoogleTest.cmake)
include(GoogleTest)
include(ExternalProject)

## Dependency: robin-hood-hashing
#

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/dep/robin-hood-hashing)

## Generating Source
#

configure_file(
    ${CMAKE_SOURCE_DIR}/inc/ss-config/config.hh.in
    ${CMAKE_SOURCE_DIR}/inc/ss-config/config.hh
)

## Configuring targets: global config
#

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/inc/
    ${CMAKE_CURRENT_SOURCE_DIR}/dep/robin-hood-hashing/src/include
)

set(CMAKE_CXX_STANDARD 20)

if (WIN32)
    # set stuff for windows
elseif(APPLE)
    
else()
    # set linux stuff
endif()


## Configuring Targets
#

# core: shared between interpreter, compiler, and run-time library.
add_library(
    ss-core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-core/object.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-core/intern.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-core/feedback.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-core/memory.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-core/gc.cc
)
target_link_libraries(
    ss-core
    robin_hood
)

# jit: compiles, evaluates partially or fully, and generates binaries 
add_library(
    ss-jit
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-jit/parser.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-jit/printing.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-jit/std.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-jit/smt.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-jit/vcode.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-jit/vthread.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-jit/vglobals.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-jit/vm.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ss-jit/compiler.cc
)
target_link_libraries(ss-jit 
    ss-core
    ${Boost_LIBRARIES} 
    ${FOLLY_LIBRARIES}
)

# ssi: Snail-Scheme interpreter
add_executable(
    ssi
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ssi/ssi.cc
)
target_link_libraries(ssi ss-core ss-jit)

# ss-tests: tests for SS
add_executable(
    ss-tests
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/TestTest.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/tests/TestObject1.cc
)
target_link_libraries(ss-tests gtest_main ss-core ss-jit)
gtest_discover_tests(ss-tests)
