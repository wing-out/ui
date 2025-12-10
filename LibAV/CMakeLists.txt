cmake_minimum_required(VERSION 3.16)

project(LibAV VERSION 0.1 LANGUAGES CXX)

find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(Qt6 REQUIRED COMPONENTS Gui)

qt_standard_project_setup(REQUIRES 6.10)

set(LIBAV_SOURCES
    encoder.h
    encoder_rtmp.h
    encoder_rtmp.cpp
    worker_encoder.h
    worker_encoder.cpp
)

add_library(LibAV STATIC
    ${LIBAV_SOURCES}
)

target_link_libraries(LibAV
    PRIVATE
    Qt6::Core # QString, QObject
    Qt6::Gui # QImage
    avformat
    avcodec
    avutil
    swscale
)

target_include_directories(LibAV
    PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)
