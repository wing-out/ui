cmake_minimum_required(VERSION 3.16)

project(LibAV VERSION 0.1 LANGUAGES CXX)

find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(Qt6 REQUIRED COMPONENTS Gui)

qt_standard_project_setup(REQUIRES 6.10)

set(LIBAV_SOURCES
    encoder.h
    rtmp_encoder.h
    rtmp_encoder.cpp
    encoder_worker.h
    encoder_worker.cpp
)

add_library(libav_stream STATIC
    ${LIBAV_SOURCES}
)

target_link_libraries(libav_stream
    PRIVATE
    Qt6::Core # QString, QObject
    Qt6::Gui # QImage
    avformat
    avcodec
    avutil
    swscale
)

target_include_directories(libav_stream
    PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)
