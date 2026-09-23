# Registers validation/ in a build of the repository without editing the
# top-level CMakeLists.txt. Pass it to the configure step:
#
#   cmake -DCMAKE_PROJECT_cuqdyn_INCLUDE=<repo>/validation/cmake/register.cmake ...
#
# project(cuqdyn) includes this file as its last step, before the library
# targets are declared. That is early but sufficient: validation/CMakeLists.txt
# only names targets (cuqdyn-c, cli_version), which CMake resolves when it
# generates, and enables testing itself. validation/run_validation.sh build
# does exactly this.
add_subdirectory(
    "${CMAKE_CURRENT_LIST_DIR}/.."
    "${CMAKE_BINARY_DIR}/validation"
)
