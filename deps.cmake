include(FetchContent)

# Building v7.30 of CVODES
include(ExternalProject)

FetchContent_Declare(
        cvodes
        URL https://github.com/LLNL/sundials/releases/download/v7.3.0/cvodes-7.3.0.tar.gz
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)

FetchContent_MakeAvailable(cvodes)


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
set(HDF5_BUILD_HL_LIB OFF CACHE BOOL "" FORCE)
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

set(HDF5_DIR "${hdf5_BINARY_DIR}/CMakeFiles")

set(HDF5_INCLUDE_DIR "${hdf5_SOURCE_DIR}/src")
set(HDF5_INCLUDE_DIRS "${hdf5_SOURCE_DIR}/src;${hdf5_BINARY_DIR}")
set(HDF5_LIBRARY "${hdf5_BINARY_DIR}/bin/libhdf5.a")
set(HDF5_LIBRARIES "${HDF5_LIBRARY}")
set(HDF5_FOUND TRUE)

set(HAVE_HDF5 TRUE CACHE BOOL "Pretend we have HDF5" FORCE)
# set(MATIO_MAT73 ON CACHE BOOL "Enable MAT73 support" FORCE)

# Building Matio dependency
set(MATIO_WITH_ZLIB ON CACHE BOOL "" FORCE)
set(MATIO_WITH_HDF5 ON CACHE BOOL "" FORCE)
set(MATIO_WITH_MAT73 ON CACHE BOOL "" FORCE)
set(MATIO_SHARED OFF CACHE BOOL "" FORCE)
set(MATIO_BUILD_TESTING OFF CACHE BOOL "" FORCE)

include_directories(${hdf5_SOURCE_DIR}/src ${hdf5_BINARY_DIR})
link_libraries(hdf5)

FetchContent_Declare(
        matio
        GIT_REPOSITORY https://github.com/tbeu/matio.git
        GIT_TAG v1.5.28
        GIT_SHALLOW TRUE
)

FetchContent_Populate(matio)

execute_process(
        COMMAND sed -i "s|find_package(HDF5)|find_package(HDF5 CONFIG)|" ${matio_SOURCE_DIR}/cmake/thirdParties.cmake
)

add_subdirectory(${matio_SOURCE_DIR} ${matio_BINARY_DIR})

## mexpeval

set(RUST_LIB_DIR "${PROJECT_SOURCE_DIR}/modules/mexpreval")
set(RUST_TARGET_DIR "${RUST_LIB_DIR}/target/release")

add_custom_target(rust_lib ALL
    env RUSTFLAGS=-C target-cpu=native
    COMMAND cargo build --release
    WORKING_DIRECTORY ${RUST_LIB_DIR}
)
