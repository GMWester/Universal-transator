# Builds GMWester/IPAReader (git submodule in ../third_party/ipareader) as a
# shared library loaded from Dart through dart:ffi.
cmake_minimum_required(VERSION 3.10)
project(ipareader_ffi_library VERSION 1.0.0 LANGUAGES C)

set(IPR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ipareader")
if(NOT EXISTS "${IPR_ROOT}/src/api.c")
  message(FATAL_ERROR "IPAReader sources missing. Run: git submodule update --init --recursive")
endif()

add_library(ipareader_ffi SHARED
  "${IPR_ROOT}/src/parse.c"
  "${IPR_ROOT}/src/plan.c"
  "${IPR_ROOT}/src/synth.c"
  "${IPR_ROOT}/src/api.c"
  "${IPR_ROOT}/src/tune.c"
)
target_include_directories(ipareader_ffi PRIVATE "${IPR_ROOT}/include" "${IPR_ROOT}/src")
target_compile_definitions(ipareader_ffi PRIVATE IPR_BUILD_DLL _CRT_SECURE_NO_WARNINGS _USE_MATH_DEFINES)
set_target_properties(ipareader_ffi PROPERTIES
  OUTPUT_NAME "ipareader_ffi"
  C_STANDARD 11
  C_VISIBILITY_PRESET hidden)
if(NOT MSVC)
  target_compile_options(ipareader_ffi PRIVATE -O2)
  target_link_libraries(ipareader_ffi PRIVATE m)
endif()
if(ANDROID)
  # Android 15+ 16 KB page size support
  target_link_options(ipareader_ffi PRIVATE "-Wl,-z,max-page-size=16384")
endif()
