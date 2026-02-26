cmake_minimum_required(VERSION 3.24)
project(lpg_runtime_benchmark LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(lpg-runtime-benchmark
  benchmark/main.cpp
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(lpg-runtime-benchmark PRIVATE -Wall -Wextra -Wpedantic -Werror)
elseif(MSVC)
  target_compile_options(lpg-runtime-benchmark PRIVATE /W4 /WX)
endif()

if(CMAKE_BUILD_TYPE)
  set(LPG_BUILD_FLAGS "${CMAKE_BUILD_TYPE}")
else()
  set(LPG_BUILD_FLAGS "default")
endif()

target_compile_definitions(lpg-runtime-benchmark PRIVATE
  LPG_RUNTIME_BUILD_FLAGS="${LPG_BUILD_FLAGS}"
)
