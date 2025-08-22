set(CMAKE_C_COMPILER gcc)
set(CMAKE_CXX_COMPILER g++)
set(CMAKE_Fortran_COMPILER gfortran)
set(CMAKE_C_FLAGS "-O2 -g -MMD -DGNU -w -UNDEBUG -DDEBUG")
set(CMAKE_Fortran_FLAGS "-O2 -g -cpp -DGNU -fallow-argument-mismatch -std=gnu")

set(MISQP_LIBRARY_DIR "${PROJECT_SOURCE_DIR}/deps/misqp/gnu")
set(LIBRARIES "")
