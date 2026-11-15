cmake_minimum_required(VERSION 3.20)
project(ThreadsStudioVoice LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(AUDIOCPP_MODEL_SET custom CACHE STRING "" FORCE)
set(AUDIOCPP_MODELS vieneu_v3_turbo CACHE STRING "" FORCE)
set(AUDIOCPP_DEPLOYMENT_BUILD ON CACHE BOOL "" FORCE)
set(AUDIOCPP_BUILD_C_API ON CACHE BOOL "" FORCE)
set(AUDIOCPP_BUILD_C_API_STATIC ON CACHE BOOL "" FORCE)
set(AUDIOCPP_BUILD_NATIVE_MODEL_MANAGER OFF CACHE BOOL "" FORCE)
set(ENGINE_ENABLE_METAL OFF CACHE BOOL "" FORCE)
set(ENGINE_ENABLE_NATIVE_CPU OFF CACHE BOOL "" FORCE)
set(ENGINE_ENABLE_OPENMP OFF CACHE BOOL "" FORCE)
set(ENGINE_ENABLE_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(ENGINE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
# SentencePiece expects the iOS toolchain's Xcode-property helper even for static Makefile builds.
function(set_xcode_property target property value variant)
    set_property(TARGET "${target}" PROPERTY "XCODE_ATTRIBUTE_${property}" "${value}")
endfunction()
add_subdirectory("${AUDIO_SOURCE}" audio EXCLUDE_FROM_ALL)
add_library(studio_voice STATIC VoiceBridge.cpp)
target_include_directories(studio_voice PRIVATE "${AUDIO_SOURCE}/include" "${SEA_SOURCE}/include")
target_link_libraries(studio_voice PRIVATE audiocpp_static "${SEA_LIBRARY}")
add_custom_command(TARGET studio_voice POST_BUILD
    COMMAND /usr/bin/libtool -static -o "${CMAKE_BINARY_DIR}/libStudioVoice.a"
    "$<TARGET_FILE:studio_voice>" "$<TARGET_FILE:audiocpp_static>" "$<TARGET_FILE:engine_runtime>"
    "$<TARGET_FILE:ggml>" "$<TARGET_FILE:ggml-base>" "$<TARGET_FILE:ggml-cpu>"
    "$<TARGET_FILE:sentencepiece>" "$<TARGET_FILE:cjson_vendor>" "$<TARGET_FILE:yaml_vendor>" "${SEA_LIBRARY}")
