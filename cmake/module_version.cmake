function(cuqdyn_module_version module)
    string(REPLACE "-" "_" stem ${module})

    set(script ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/gen_module_version.cmake)
    set(args
        -DSOURCE_DIR=${PROJECT_SOURCE_DIR}
        -DMODULE=${module}
        -DTEMPLATE=${CMAKE_CURRENT_SOURCE_DIR}/include/${stem}_version.in.h
        -DHEADER=${CMAKE_CURRENT_SOURCE_DIR}/generated/${stem}_version.h
    )

    execute_process(COMMAND ${CMAKE_COMMAND} ${args} -P ${script})

    add_custom_target(
        ${stem}_version
        ALL
        COMMAND ${CMAKE_COMMAND} ${args} -P ${script}
        BYPRODUCTS ${CMAKE_CURRENT_SOURCE_DIR}/generated/${stem}_version.h
        COMMENT "Checking ${module} version"
    )
endfunction()
