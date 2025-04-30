execute_process(
        COMMAND bash -c "
        branch=\$(git rev-parse --abbrev-ref HEAD)
        version=\$(git tag --sort=-creatordate | grep '^cli/' | head -n 1 | sed -E 's:.*/(v[0-9]+\.[0-9]+\.[0-9]+):\\1:')
        if [ \"\$branch\" = \"main\" ]; then
            echo \"\$version\"
        else
            if [ -n \"\$version\" ]; then
                echo \"\$version-$branch\"
            else
                echo \"dev\"
            fi
        fi
    "
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_VERSION
        RESULT_VARIABLE TAG_RESULT
        OUTPUT_STRIP_TRAILING_WHITESPACE
)

if (NOT TAG_RESULT EQUAL 0 OR GIT_VERSION STREQUAL "")
    set(GIT_VERSION "dev")
endif ()

configure_file(
        include/cuqdyn_version.in.h
        ${PROJECT_SOURCE_DIR}/modules/cuqdyn-c/generated/cuqdyn_version.h
)

message(STATUS "CUQDYN_C_VERSION: ${GIT_VERSION}")
add_definitions(-DCUQDYN_C_VERSION=\"${GIT_VERSION}\")

file(GLOB LIB_SRC CONFIGURE_DEPENDS src/*.c src/functions/*.c)

add_library(cuqdyn-c
        ${LIB_SRC}
)

target_include_directories(cuqdyn-c
        PUBLIC
        include
        generated
)

target_link_libraries(cuqdyn-c
        sacess
        matio
)
