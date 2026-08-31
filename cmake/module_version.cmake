function(cuqdyn_module_version module basename)
    set(script ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/gen_module_version.cmake)
    set(args
        -DSOURCE_DIR=${PROJECT_SOURCE_DIR}
        -DMODULE=${module}
        -DTEMPLATE=${CMAKE_CURRENT_SOURCE_DIR}/include/${basename}.in.h
        -DHEADER=${CMAKE_CURRENT_SOURCE_DIR}/generated/${basename}.h
    )

    execute_process(COMMAND ${CMAKE_COMMAND} ${args} -P ${script})

    add_custom_target(
        ${module}_version
        ALL
        COMMAND ${CMAKE_COMMAND} ${args} -P ${script}
        BYPRODUCTS ${CMAKE_CURRENT_SOURCE_DIR}/generated/${basename}.h
        COMMENT "Checking ${module} version"
    )
endfunction()
