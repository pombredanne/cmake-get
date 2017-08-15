
set(BUILD_DEPS On CACHE BOOL "Build dependencies")

include(ProcessorCount)

if(CMAKE_VERSION VERSION_LESS "3.4")
function(cget_parse_arguments prefix _optionNames _singleArgNames _multiArgNames)
    # first set all result variables to empty/FALSE
    foreach(arg_name ${_singleArgNames} ${_multiArgNames})
        set(${prefix}_${arg_name})
    endforeach()

    foreach(option ${_optionNames})
        set(${prefix}_${option} FALSE)
    endforeach()

    set(${prefix}_UNPARSED_ARGUMENTS)

    set(insideValues FALSE)
    set(currentArgName)

    # now iterate over all arguments and fill the result variables
    foreach(currentArg ${ARGN})
        list(FIND _optionNames "${currentArg}" optionIndex)  # ... then this marks the end of the arguments belonging to this keyword
        list(FIND _singleArgNames "${currentArg}" singleArgIndex)  # ... then this marks the end of the arguments belonging to this keyword
        list(FIND _multiArgNames "${currentArg}" multiArgIndex)  # ... then this marks the end of the arguments belonging to this keyword

        if(${optionIndex} EQUAL -1  AND  ${singleArgIndex} EQUAL -1  AND  ${multiArgIndex} EQUAL -1)
            if(insideValues)
                if("${insideValues}" STREQUAL "SINGLE")
                    set(${prefix}_${currentArgName} ${currentArg})
                    set(insideValues FALSE)
                elseif("${insideValues}" STREQUAL "MULTI")
                    list(APPEND ${prefix}_${currentArgName} ${currentArg})
                endif()
            else()
                list(APPEND ${prefix}_UNPARSED_ARGUMENTS ${currentArg})
            endif()
        else()
            if(NOT ${optionIndex} EQUAL -1)
                set(${prefix}_${currentArg} TRUE)
                set(insideValues FALSE)
            elseif(NOT ${singleArgIndex} EQUAL -1)
                set(currentArgName ${currentArg})
                set(${prefix}_${currentArgName})
                set(insideValues "SINGLE")
            elseif(NOT ${multiArgIndex} EQUAL -1)
                set(currentArgName ${currentArg})
                set(insideValues "MULTI")
            endif()
        endif()

    endforeach()

    # propagate the result variables to the caller:
    foreach(arg_name ${_singleArgNames} ${_multiArgNames} ${_optionNames})
        set(${prefix}_${arg_name}  ${${prefix}_${arg_name}} PARENT_SCOPE)
    endforeach()
    set(${prefix}_UNPARSED_ARGUMENTS ${${prefix}_UNPARSED_ARGUMENTS} PARENT_SCOPE)

endfunction()
else()
    macro(cget_parse_arguments prefix _optionNames _singleArgNames _multiArgNames)
        cmake_parse_arguments(${prefix} "${_optionNames}" "${_singleArgNames}" "${_multiArgNames}" ${ARGN})
    endmacro()
endif()

set(_cget_tmp_dir "${CMAKE_CURRENT_LIST_DIR}/tmp")
foreach(dir "$ENV{TMP}" "$ENV{TMPDIR}" "/tmp")
    if(EXISTS "${dir}" AND NOT "${dir}" STREQUAL "")
        set(_cget_tmp_dir ${dir})
        break()
    endif()
endforeach()
set(_tmp_dir_count 0)

macro(cget_mktemp_dir OUT)
    string(TIMESTAMP cget_mktemp_dir_STAMP "%H-%M-%S")
    string(RANDOM cget_mktemp_dir_RAND)
    set(cget_mktemp_dir_PREFIX "${_cget_tmp_dir}/cget-${cget_mktemp_dir_STAMP}-${cget_mktemp_dir_RAND}")
    math(EXPR _tmp_dir_count "${_tmp_dir_count} + 1")
    set(${OUT} "${cget_mktemp_dir_PREFIX}-${_tmp_dir_count}")
    file(MAKE_DIRECTORY ${${OUT}})
endmacro()

macro(cget_set_parse_flag VAR OPT)
    foreach(FLAG ${ARGN})
        if(${VAR}_private_${FLAG})
            set(${VAR}_${OPT} ${${VAR}_private_${FLAG}})
        endif()
    endforeach()
endmacro()

macro(cget_parse_requirement VAR PKG)
    set(${VAR}_PKG ${PKG})
    set(${VAR}_private_options --build -b --test -t)
    set(${VAR}_private_oneValueArgs -H --hash -X --cmake)
    set(${VAR}_private_multiValueArgs -D --define)

    set(cget_parse_requirement_args)
    foreach(ARG ${ARGN})
        if(ARG MATCHES "^-([^-])(.+)")
            list(APPEND cget_parse_requirement_args -${CMAKE_MATCH_1})
            list(APPEND cget_parse_requirement_args ${CMAKE_MATCH_2})
        else()
            list(APPEND cget_parse_requirement_args ${ARG})
        endif()
    endforeach()

    cget_parse_arguments(${VAR}_private "${${VAR}_private_options}" "${${VAR}_private_oneValueArgs}" "${${VAR}_private_multiValueArgs}" ${cget_parse_requirement_args})

    cget_set_parse_flag(${VAR} BUILD --build -b)
    cget_set_parse_flag(${VAR} TEST --test -t)
    cget_set_parse_flag(${VAR} CMAKE --cmake -X)
    cget_set_parse_flag(${VAR} HASH --hash -H)
    cget_set_parse_flag(${VAR} DEFINE --define -D)
    set(${VAR}_CMAKE_ARGS)
    foreach(DEFINE ${${VAR}_DEFINE})
        list(APPEND ${VAR}_CMAKE_ARGS "-D${DEFINE}")
    endforeach()
endmacro()

function(cget_exec)
    execute_process(${ARGN} RESULT_VARIABLE RESULT)
    if(NOT RESULT EQUAL 0)
        message(FATAL_ERROR "Process failed: ${ARGN}")
    endif()
endfunction()

function(cget_download)
    file(DOWNLOAD ${ARGN} STATUS RESULT_LIST)
    list(GET RESULT_LIST 0 RESULT)
    list(GET RESULT_LIST 1 RESULT_MESSAGE)
    if(NOT RESULT EQUAL 0)
        message(FATAL_ERROR "Download failed: ${RESULT_MESSAGE}: ${ARGN}")
    endif()
endfunction()

set(_cget_install_dir_count 0)
set_property(GLOBAL PROPERTY _cget_install_dir_count 0)
function(cget_install_dir DIR)
    set(options)
    set(oneValueArgs PREFIX BUILD_DIR)
    set(multiValueArgs CMAKE_ARGS)

    cget_parse_arguments(PARSE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    set(PREFIX ${PARSE_PREFIX})
    set(BUILD_DIR ${PARSE_BUILD_DIR})
    if(NOT EXISTS ${BUILD_DIR})
        file(MAKE_DIRECTORY ${BUILD_DIR})
    endif()
    cget_exec(COMMAND ${CMAKE_COMMAND} 
        -DCMAKE_PREFIX_PATH=${PREFIX} 
        -DCMAKE_INSTALL_PREFIX=${PREFIX}
        ${PARSE_CMAKE_ARGS}
        ${DIR}
        WORKING_DIRECTORY ${BUILD_DIR}
    )
    set(BUILD_ARGS)
    if(EXISTS ${BUILD_DIR}/Makefile)
        ProcessorCount(N)
        set(BUILD_ARGS -- -j ${N})
    endif()
    cget_exec(COMMAND ${CMAKE_COMMAND} --build ${BUILD_DIR} ${BUILD_ARGS})
    cget_exec(COMMAND ${CMAKE_COMMAND} --build ${BUILD_DIR} --target install ${BUILD_ARGS})

    get_property(_tmp_count GLOBAL PROPERTY _cget_install_dir_count)
    math(EXPR _tmp_count "${_tmp_count} + 1")
    set_property(GLOBAL PROPERTY _cget_install_dir_count ${_tmp_count})

    file(REMOVE_RECURSE ${BUILD_DIR})
endfunction()

function(cget_parse_src_name URL VARIANT SRC)
    if(SRC MATCHES "@")
        string(REPLACE "@" ";" SRC_LIST ${SRC})
        list(GET SRC_LIST 0 _URL)
        list(GET SRC_LIST 1 _VARIANT)
        set(${URL} ${_URL} PARENT_SCOPE)
        set(${VARIANT} ${_VARIANT} PARENT_SCOPE)
    else()
        set(${URL} ${SRC} PARENT_SCOPE)
        set(${VARIANT} ${ARGN} PARENT_SCOPE)
    endif()
endfunction()

function(cget_find_recipe RECIPE_DIR SRC)
    cget_parse_src_name(NAME VARIANT ${SRC})
    foreach(RECIPE ${ARGN})
        if(EXISTS ${RECIPE}/${NAME}/package.txt OR EXISTS ${RECIPE}/${NAME}/requirements.txt)
            # TODO: Check variant
            set(${RECIPE_DIR} ${RECIPE}/${NAME} PARENT_SCOPE)
            break()
        endif()
    endforeach()
endfunction()

function(cget_parse_pkg NAME URL PKG)
    string(REPLACE "," ";" PKG_NAMES ${PKG})
    list(GET PKG_NAMES -1 PKG_SRC)
    list(GET PKG_NAMES 0 PKG_NAME)
    set(${NAME} ${PKG_NAME} PARENT_SCOPE)
    if(PKG_SRC MATCHES "://")
        set(${URL} ${PKG_SRC} PARENT_SCOPE)
    else()
        get_filename_component(PKG_SRC_FULL ${PKG_SRC} ABSOLUTE)
        if(EXISTS ${PKG_SRC_FULL})
            set(${URL} file://${PKG_SRC_FULL} PARENT_SCOPE)
        else()
            # Parse recipe dir
            cget_find_recipe(RECIPE_DIR ${PKG_SRC} ${ARGN})
            if(EXISTS ${RECIPE_DIR})
                set(${URL} recipe://${RECIPE_DIR} PARENT_SCOPE)
                set(${NAME} ${PKG_SRC} ${PKG_NAME} PARENT_SCOPE)
            else()
                # Parse github url
                cget_parse_src_name(GH_NAME GH_BRANCH ${PKG_SRC} HEAD)
                set(${NAME} ${GH_NAME} ${PKG_NAME} PARENT_SCOPE)
                if(GH_NAME MATCHES "/")
                    set(${URL} "https://github.com/${GH_NAME}/archive/${GH_BRANCH}.tar.gz" PARENT_SCOPE)
                else()
                    set(${URL} "https://github.com/${GH_NAME}/${GH_NAME}/archive/${GH_BRANCH}.tar.gz" PARENT_SCOPE)
                endif()
            endif()
        endif()
    endif()
endfunction()

function(cget_fetch DIR DOWNLOAD_DIR URL)
    if("${URL}" MATCHES "file://")
        string(REPLACE "file://" "" LOCAL_DIR ${URL})
        file(COPY ${LOCAL_DIR} DESTINATION ${DOWNLOAD_DIR}/)
    else()
        string(REPLACE "/" ";" PATH_LIST ${URL})
        
        list(GET PATH_LIST -1 FILENAME)
        message("Downloading ${URL}")
        cget_download(${URL} ${DOWNLOAD_DIR}/${FILENAME} ${ARGN})
        execute_process(COMMAND ${CMAKE_COMMAND} -E tar xzf ${DOWNLOAD_DIR}/${FILENAME}
            WORKING_DIRECTORY ${DOWNLOAD_DIR}
        )
        file(REMOVE ${DOWNLOAD_DIR}/${FILENAME})
    endif()
    file(GLOB FILES LIST_DIRECTORIES true RELATIVE ${DOWNLOAD_DIR} ${DOWNLOAD_DIR}/*)
    list(LENGTH FILES NFILES)
    if(NFILES GREATER 0)
        list(GET FILES 0 _DIR)
        set(${DIR} ${DOWNLOAD_DIR}/${_DIR} PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Failed to fetch: ${URL}")
    endif()
endfunction()

set(_cget_cmake_original_file "__cget_original_cmake_file__.cmake")
function(cget_find_cmake FILE DIR)
    if(EXISTS ${DIR}/CMakeLists.txt)
        file(RENAME ${DIR}/CMakeLists.txt ${DIR}/${_cget_cmake_original_file})
    endif()
    get_filename_component(BASENAME ${FILE} NAME)
    if(EXISTS ${FILE})
        file(COPY ${FILE} DESTINATION ${DIR}/)
        file(RENAME ${DIR}/${BASENAME} ${DIR}/CMakeLists.txt)
    else()
        string(REPLACE ".cmake" "" REMOTE_CMAKE ${BASENAME})
        cget_download(https://raw.githubusercontent.com/pfultz2/cget/master/cget/cmake/${REMOTE_CMAKE}.cmake ${DIR}/CMakeLists.txt)
    endif()
endfunction()

function(cget_check_pkg_install FOUND)
    get_property(INSTALLED_PKGS GLOBAL PROPERTY CGET_INSTALLED_PACKAGES)
    set(FOUND 0 PARENT_SCOPE)
    foreach(NAME ${ARGN})
        list(FIND INSTALLED_PKGS ${NAME} IDX)
        if(IDX EQUAL "-1")
            set_property(GLOBAL APPEND PROPERTY CGET_INSTALLED_PACKAGES ${NAME})
        else()
            set(FOUND 1 PARENT_SCOPE)
        endif()
    endforeach()
endfunction()

function(cmake_get PKG)
if(BUILD_DEPS)
    set(options NO_RECIPE)
    set(oneValueArgs PREFIX HASH CMAKE_FILE)
    set(multiValueArgs CMAKE_ARGS)
    
    cget_parse_arguments(PARSE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    if(PARSE_NO_RECIPE)
        cget_parse_pkg(NAMES URL ${PKG})
    else()
        cget_parse_pkg(NAMES URL ${PKG} ${PARSE_PREFIX}/etc/cget/recipes)
    endif()
    cget_check_pkg_install(FOUND ${NAMES})
    if(NOT FOUND)

        if(URL MATCHES "recipe://")
            string(REPLACE "recipe://" "" RECIPE ${URL})
            if(EXISTS ${RECIPE}/requirements.txt)
                cmake_get_from(${RECIPE}/requirements.txt PREFIX ${PARSE_PREFIX} CMAKE_ARGS ${PARSE_CMAKE_ARGS})
            endif()
            if(EXISTS ${RECIPE}/package.txt)
                cmake_get_from(${RECIPE}/package.txt PREFIX ${PARSE_PREFIX} CMAKE_ARGS ${PARSE_CMAKE_ARGS} NO_RECIPE)
            endif()
        else()
            cget_mktemp_dir(TMP_DIR)

            if(PREFIX_HASH)
                string(TOUPPER ${PREFIX_HASH} _HASH)
                string(REPLACE ":" "=" _HASH ${_HASH})
                set(HASH EXPECTED_HASH ${_HASH})
            endif()

            cget_fetch(DIR ${TMP_DIR}/download ${URL} ${HASH} SHOW_PROGRESS)
            if(EXISTS ${DIR}/requirements.txt)
                cmake_get_from(${DIR}/requirements.txt ${BASE_DIR_ARG} PREFIX ${PARSE_PREFIX} CMAKE_ARGS ${PARSE_CMAKE_ARGS})
            endif()
            if(PARSE_CMAKE_FILE)
                cget_find_cmake(${PARSE_CMAKE_FILE} ${DIR})
            endif()
            cget_install_dir(${DIR} BUILD_DIR ${TMP_DIR}/build PREFIX ${PARSE_PREFIX} CMAKE_ARGS -DCGET_CMAKE_ORIGINAL_SOURCE_FILE=${DIR}/${_cget_cmake_original_file} ${PARSE_CMAKE_ARGS})

            file(REMOVE_RECURSE ${TMP_DIR})
        endif()
    endif()
endif()
endfunction()

set(_cmake_get_configure_reqs 0)
function(cmake_get_from FILENAME)
if(BUILD_DEPS)
    set(options NO_RECIPE)
    set(oneValueArgs PREFIX)
    set(multiValueArgs CMAKE_ARGS)
    cget_parse_arguments(PARSE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    file(STRINGS ${FILENAME} LINES)
    foreach(LINE ${LINES})
        separate_arguments(WORDS UNIX_COMMAND "${LINE}")
        set(REQ)
        foreach(WORD ${WORDS})
            if(WORD MATCHES "^#")
                break()
            endif()
            list(APPEND REQ ${WORD})
        endforeach()
        list(LENGTH REQ REQ_LEN)
        if(REQ_LEN GREATER 0)
            cget_parse_requirement(PARSE_REQ ${REQ})
            if(_cmake_get_configure_reqs)
                string(CONFIGURE ${PARSE_REQ_PKG} PARSE_REQ_PKG @ONLY)
            endif()
            if(PARSE_NO_RECIPE)
                set(NO_RECIPE "NO_RECIPE")
            endif()
            if(PARSE_REQ_CMAKE)
                get_filename_component(FILE_DIR ${FILENAME} DIRECTORY)
                if(NOT IS_ABSOLUTE PARSE_REQ_CMAKE)
                    set(REQ_CMAKE "${FILE_DIR}/${PARSE_REQ_CMAKE}")
                else()
                    set(REQ_CMAKE "${PARSE_REQ_CMAKE}")
                endif()
            endif()
            cmake_get(${PARSE_REQ_PKG}
                ${NO_RECIPE}
                PREFIX ${PARSE_PREFIX} 
                HASH ${PARSE_REQ_HASH}
                CMAKE_FILE ${REQ_CMAKE}
                CMAKE_ARGS ${PARSE_CMAKE_ARGS} ${PARSE_REQ_CMAKE_ARGS}
            )
        endif()
    endforeach()
endif()
endfunction()
