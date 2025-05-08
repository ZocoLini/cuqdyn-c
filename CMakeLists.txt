cmake_minimum_required(VERSION 3.11)

project(cuqdyn LANGUAGES C Fortran CXX)
include(FetchContent)

#####################################################################
## saCeSS solver
# set(CMAKE_C_COMPILER mpicc)
# set(CMAKE_Fortran_COMPILER mpif90)
# set(CMAKE_C_FLAGS "-O3 -cpp -DGNU -fPIC -no-pie -DOPENMP -DMPI2 -fopenmp -lmpi")
# set(CMAKE_Fortran_FLAGS "-O3 -cpp -DGNU  -fallow-argument-mismatch -std=gnu -DOPENMP -DMPI2 -DGNU -fopenmp")
#
# set(MISQP_LIBRARY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/deps/misqp/gnu")
# set(LIBRARIES mpi ifcore ifport imf)
######################################################################

######################################################################
## ScatterSearch solver
# set(CMAKE_C_COMPILER icc)
# set(CMAKE_Fortran_COMPILER ifort)
# set(CMAKE_C_FLAGS "-O3 -ipo -xHost -DINTEL -diag-disable=10441")
# set(CMAKE_Fortran_FLAGS "-O3 -ipo -xHost -fpp -DEXPORT -DINTEL")
#
# set(MISQP_LIBRARY_DIR "${PROJECT_SOURCE_DIR}/deps/misqp/intel")
# set(LIBRARIES ifcore)
######################################################################

######################################################################
## ScatterSearch solver
# set(CMAKE_C_COMPILER gcc)
# set(CMAKE_CXX_COMPILER g++)
# set(CMAKE_Fortran_COMPILER gfortran)
set(CMAKE_C_FLAGS "-O1 -MMD -DGNU")
set(CMAKE_Fortran_FLAGS "-O3 -cpp -DGNU -fallow-argument-mismatch -std=gnu -w")

set(MISQP_LIBRARY_DIR "${PROJECT_SOURCE_DIR}/deps/misqp/gnu")
set(LIBRARIES "")
######################################################################

set(CMAKE_C_STANDARD 11)

# Building GSL dependency
find_package(GSL 2.7)

if (NOT GSL_FOUND)
    set(GSL_DISABLE_TESTS 1)
    FetchContent_Declare(
        gsl
        GIT_REPOSITORY https://github.com/ampl/gsl.git
        GIT_TAG v2.7.0
        GIT_SHALLOW TRUE
    )
    FetchContent_MakeAvailable(gsl)
    set(GSL_INCLUDE_DIR ${gsl_SOURCE_DIR} ${gsl_BINARY_DIR})
    set(GSL_LIBRARY "gsl")
else()
    set(GSL_LIBRARY "GSL::gsl")
endif()

# HDF5 dependency

set(HDF5_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(HDF5_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(HDF5_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(HDF5_BUILD_HL_LIB ON CACHE BOOL "" FORCE)
set(HDF5_ENABLE_Z_LIB_SUPPORT OFF CACHE BOOL "" FORCE)
set(HDF5_ENABLE_SZIP_SUPPORT OFF CACHE BOOL "" FORCE)
set(HDF5_ENABLE_THREADSAFE OFF CACHE BOOL "" FORCE)
set(HDF5_ENABLE_PARALLEL OFF CACHE BOOL "" FORCE)
set(HDF5_ENABLE_CPP_LIB OFF CACHE BOOL "" FORCE)
set(HDF5_DEFAULT_API_VERSION v18 CACHE STRING "")

FetchContent_Declare(
    hdf5
    GIT_REPOSITORY https://github.com/HDFGroup/hdf5.git
    GIT_TAG hdf5-1_8_12
    GIT_SHALLOW TRUE
)

FetchContent_MakeAvailable(hdf5)

set(HDF5_FOUND TRUE CACHE BOOL "HDF5 found" FORCE)
set(HDF5_INCLUDE_DIRS "${hdf5_SOURCE_DIR}/src" "${hdf5_BINARY_DIR}" CACHE PATH "HDF5 includes" FORCE)
set(HDF5_LIBRARIES "${hdf5_BINARY_DIR}/src/libhdf5.a" "${hdf5_BINARY_DIR}/src/libhdf5_hl.a" CACHE STRING "HDF5 libs" FORCE)

set(HAVE_HDF5 TRUE CACHE BOOL "Pretend we have HDF5" FORCE)
set(MATIO_MAT73 ON CACHE BOOL "Enable MAT73 support" FORCE)

# Building Matio dependency
set(MATIO_WITH_ZLIB OFF CACHE BOOL "" FORCE)
set(MATIO_WITH_HDF5 OFF CACHE BOOL "" FORCE)
set(MATIO_WITH_MAT73 ON CACHE BOOL "" FORCE)
set(MATIO_SHARED OFF CACHE BOOL "" FORCE)

include_directories(${hdf5_SOURCE_DIR}/src ${hdf5_BINARY_DIR})

FetchContent_Declare(
        matio
        GIT_REPOSITORY https://github.com/tbeu/matio.git
        GIT_TAG v1.5.28
        GIT_SHALLOW TRUE
)

FetchContent_MakeAvailable(matio)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY .)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY .)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY .)

add_subdirectory(modules/cvodes_old)
add_subdirectory(modules/sacess)
add_subdirectory(modules/cuqdyn-c)
add_subdirectory(modules/cli)
add_subdirectory(modules/dotmat-introspector)

enable_testing()

add_subdirectory(tests)
