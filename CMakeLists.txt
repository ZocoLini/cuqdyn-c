cmake_minimum_required(VERSION 3.22.1)

project(ess-c LANGUAGES C Fortran)

#####################################################################
## saCeSS solver
# set(CMAKE_C_COMPILER mpicc)
# set(CMAKE_Fortran_COMPILER mpif90)
# set(CMAKE_C_FLAGS "-O3 -cpp -DGNU -fPIC -no-pie -DOPENMP -DMPI2 -fopenmp -lmpi")
# set(CMAKE_Fortran_FLAGS "-O3 -cpp -DGNU  -fallow-argument-mismatch -std=gnu -DOPENMP -DMPI2 -DGNU -fopenmp")
#
# set(MISQP_LIBRARY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/deps/misqp/gnu")
######################################################################

######################################################################
## ScatterSearch solver
set(CMAKE_C_COMPILER icc)
set(CMAKE_Fortran_COMPILER ifort)
set(CMAKE_C_FLAGS "-O3 -ipo -xHost -DINTEL -cxxlib -lrt -MMD -lz -diag-disable=10441")
set(CMAKE_Fortran_FLAGS "-O3 -ipo -xHost -fpp -DEXPORT -DINTEL -cxxlib")

set(MISQP_LIBRARY_DIR "${PROJECT_SOURCE_DIR}/deps/misqp/intel")
######################################################################


set(CMAKE_C_STANDARD 11)

find_package(PkgConfig REQUIRED)
pkg_check_modules(MATIO REQUIRED matio)

enable_testing()

add_subdirectory(modules/cvodes_old)
add_subdirectory(modules/sacess)
add_subdirectory(modules/cli)
add_subdirectory(modules/cli-lib)
add_subdirectory(modules/dotmat-introspector)
add_subdirectory(modules/cuqdyn-c)

add_subdirectory(tests)
