execute_process(
        COMMAND bash ${CMAKE_SOURCE_DIR}/scripts/get_module_version.sh cli
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_VERSION
        RESULT_VARIABLE TAG_RESULT
        OUTPUT_STRIP_TRAILING_WHITESPACE
)

if (NOT TAG_RESULT EQUAL 0 OR GIT_VERSION STREQUAL "")
    set(GIT_VERSION "dev")
endif()

message(STATUS "CLI_VERSION: ${GIT_VERSION}")
add_definitions(-DCLI_VERSION=\"${GIT_VERSION}\")

file(GLOB CLI_SRC CONFIGURE_DEPENDS src/*.c src/handlers/*.c)

include_directories(cli
        include
)

add_executable(cli
        ${CLI_SRC}
)

target_link_libraries(cli
        PRIVATE
        cuqdyn-c
)
