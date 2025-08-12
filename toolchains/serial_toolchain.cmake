set(CMAKE_C_COMPILER gcc)
set(CMAKE_CXX_COMPILER g++)
set(CMAKE_Fortran_COMPILER gfortran)
set(CMAKE_C_FLAGS "-O3 -MMD -DGNU -w")
set(CMAKE_Fortran_FLAGS "-O3 -cpp -DGNU -fallow-argument-mismatch -std=gnu")

set(MISQP_LIBRARY_DIR "${PROJECT_SOURCE_DIR}/deps/misqp/gnu")
set(LIBRARIES "")