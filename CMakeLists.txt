cmake_minimum_required(VERSION 2.8.12)
project(snappy)

include(CMakePrintHelpers)

set(CMAKE_DEBUG_POSTFIX d)

if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/snappy)
    find_package(Git QUIET REQUIRED)
    execute_process(
        COMMAND ${GIT_EXECUTABLE}
            clone --depth 1 https://github.com/google/snappy ${CMAKE_CURRENT_SOURCE_DIR}/snappy
        RESULT_VARIABLE r)
    if(r)
        message(FATAL_ERROR "git-cloning snappy failed.")
    endif()
endif()

set(repo ${CMAKE_CURRENT_SOURCE_DIR}/snappy)

file(STRINGS ${repo}/configure.ac cac)

# parse version numbers
set(wsp "[ \t]*")
set(digits "[0-9]+")
string(REGEX MATCH "m4_define\\(\\[snappy_major\\],${wsp}\\[(${digits})\\]\\)" _ "${cac}")
set(snappy_major ${CMAKE_MATCH_1})
string(REGEX MATCH "m4_define\\(\\[snappy_minor\\],${wsp}\\[(${digits})\\]\\)" _ "${cac}")
set(snappy_minor ${CMAKE_MATCH_1})
string(REGEX MATCH "m4_define\\(\\[snappy_patchlevel\\],${wsp}\\[(${digits})\\]\\)" _ "${cac}")
set(snappy_patchlevel ${CMAKE_MATCH_1})
string(REGEX MATCH "m4_define\\(\\[snappy_ltversion\\],${wsp}\\[(${digits}:${digits}:${digits})\\]\\)" _ "${cac}")
set(snappy_ltversion ${CMAKE_MATCH_1})

foreach(v snappy_major snappy_minor snappy_patchlevel snappy_ltversion)
    if(${v} STREQUAL "")
        message(FATAL_ERROR "Failed to parse ${v}")
    endif()
endforeach()

include(CheckTypeSize)
check_type_size(size_t HAVE_SIZE_T)
check_type_size(ssize_t HAVE_SSIZE_T)

include(CheckIncludeFile)
foreach(hdr stdint.h stddef.h sys/uio.h
    sys/mman.h sys/resource.h windows.h byteswap.h
    sys/byteswap.h sys/endian.h sys/time.h windows.h
)
    string(MAKE_C_IDENTIFIER "${hdr}" c_ident)
    string(TOUPPER "HAVE_${c_ident}" have_var)
    set(ac_var "ac_cv_have_${c_ident}")
    check_include_file(${hdr} ${have_var})
    if(${have_var})
        set(${ac_var} 1)
    else()
        set(${ac_var} 0)
    endif()
endforeach()

set(SNAPPY_MAJOR "${snappy_major}")
set(SNAPPY_MINOR "${snappy_minor}")
set(SNAPPY_PATCHLEVEL "${snappy_patchlevel}")

configure_file(${repo}/snappy-stubs-public.h.in snappy-stubs-public.h @ONLY)

include(CheckFunctionExists)
check_function_exists(mmap HAVE_MMAP)

find_package(gtest QUIET) # not tested
if(gtest_FOUND)
    set(HAVE_GTEST 1)
endif()

option("Use the gflags package for command-line parsing." WITH_GFLAGS)
if(WITH_GFLAGS)
    find_package(gflags REQUIRED)
    set(HAVE_GFLAGS 1)
endif()

include(TestBigEndian)
include(CheckCSourceCompiles)

check_c_source_compiles("int main() { __builtin_ctz(0); return 0; }" HAVE_BUILTIN_CTZ)
check_c_source_compiles("int main() { __builtin_expect(0, 0); return 0; }" HAVE_BUILTIN_EXPECT)

# unittest libs not added
set(HAVE_LIBFASTLZ 0)
set(HAVE_LIBLZF 0)
set(HAVE_LIBLZO2 0)
set(HAVE_LIBQUICKLZ 0)

# don't try to use ZLIB (should work, though)
#find_package(ZLIB QUIET)
#if(ZLIB_FOUND)
#    set(HAVE_LIBZ 1)
#endif()

set(AC_APPLE_UNIVERSAL_BUILD 0)

set(cfg ${CMAKE_CURRENT_BINARY_DIR}/config.h)
file(WRITE ${cfg} "")

foreach(hh
    HAVE_BUILTIN_CTZ
    HAVE_BUILTIN_EXPECT
    HAVE_BYTESWAP_H
    HAVE_GFLAGS
    HAVE_GTEST
    HAVE_LIBFASTLZ
    HAVE_LIBLZF
    HAVE_LIBLZO2
    HAVE_LIBQUICKLZ
    HAVE_LIBZ
    HAVE_SYS_ENDIAN_H
    HAVE_SYS_MMAN_H
    HAVE_SYS_RESOURCE_H
    HAVE_SYS_TIME_H
    HAVE_WINDOWS_H
)
    if(${hh})
        file(APPEND ${cfg} "#define ${hh}\n")
    else()
        file(APPEND ${cfg} "/* #undef ${hh} */\n")
    endif()
endforeach()

if(HAVE_SIZE_T)
    file(APPEND ${cfg} "/* #undef size_t */\n")
else()
    file(APPEND ${cfg} "#define size_t unsigned int\n")
endif()

if(HAVE_SSIZE_T)
    file(APPEND ${cfg} "/* #undef ssize_t */\n")
else()
    file(APPEND ${cfg} "#define ssize_t int\n")
endif()

set(libsnappy_la_SOURCES snappy.cc snappy-sinksource.cc snappy-stubs-internal.cc snappy-c.cc)
set(include_HEADERS snappy.h snappy-sinksource.h snappy-c.h)
set(noinst_HEADERS snappy-internal.h snappy-stubs-internal.h)

foreach(u libsnappy_la_SOURCES include_HEADERS noinst_HEADERS)
    set(l "${${u}}")
    unset(${u})
    foreach(f IN LISTS l)
        list(APPEND ${u} "${repo}/${f}")
    endforeach()
endforeach()

list(APPEND include_HEADERS "${CMAKE_CURRENT_BINARY_DIR}/snappy-stubs-public.h")
list(APPEND noinst_HEADERS "${CMAKE_CURRENT_BINARY_DIR}/config.h")

add_definitions(-DHAVE_CONFIG_H)

add_library(snappy
    ${libsnappy_la_SOURCES}
    ${include_HEADERS}
    ${noinst_HEADERS})
target_include_directories(snappy
    PUBLIC
        $<BUILD_INTERFACE:${repo}>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}>
        $<INSTALL_INTERFACE:include>
)

if(NOT UNIX AND NOT BUILD_SHARED_LIBS)
    set_target_properties(snappy PROPERTIES OUTPUT_NAME libsnappy)
endif()

install(FILES ${include_HEADERS} DESTINATION include)
install(TARGETS snappy EXPORT snappy-targets
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin)

install(EXPORT snappy-targets
    FILE snappy-config.cmake
    DESTINATION lib/cmake/snappy)

# this is not added:
# libsnappy_la_LDFLAGS = -version-info ${snappy_ltversion}

# Unit tests and benchmarks.
add_executable(snappy_unittest
    ${repo}/snappy_unittest.cc
    ${repo}/snappy-test.cc
    ${repo}/snappy-test.h
)
foreach(t gtest gflags)
    if(TARGET ${t})
        target_link_libraries(snappy_unittest ${t})
    endif()
endforeach()
target_include_directories(snappy_unittest PRIVATE ${ZLIB_INCLUDE_DIRS})
target_compile_definitions(snappy_unittest PRIVATE ${ZLIB_DEFINITIONS})
target_link_libraries(snappy_unittest snappy ${ZLIB_LIBRARIES})

enable_testing()
add_test(NAME snappy_unittest
    COMMAND snappy_unittest
    WORKING_DIRECTORY ${repo})






