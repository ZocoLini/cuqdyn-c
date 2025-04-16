cmake_minimum_required(VERSION 3.22.1)

project(ess-c LANGUAGES C Fortran)

set(CMAKE_C_COMPILER icc)
set(CMAKE_Fortran_COMPILER ifort)

set(CMAKE_C_FLAGS "-O3 -ipo -xHost -DINTEL -diag-disable=10441")
set(CMAKE_Fortran_FLAGS "-O3 -ipo -xHost -fpp -DEXPORT -DINTEL")

set(CMAKE_C_STANDARD 11)
set(SUNDIALS_DIR "${PROJECT_SOURCE_DIR}/deps/cvode-7.2.1/lib/cmake/sundials")

find_package(SUNDIALS REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(MATIO REQUIRED matio)

enable_testing()

add_subdirectory(sacess)
add_subdirectory(cli)
add_subdirectory(cli-lib)
add_subdirectory(dotmat-introspector)
add_subdirectory(lib)
add_subdirectory(tests)
