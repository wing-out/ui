

find_package(Qt6 REQUIRED COMPONENTS Core Gui Multimedia)

qt_add_library(StreamingController STATIC)

qt_add_qml_module(StreamingController
    URI StreamingController
    VERSION 1.0
    SOURCES
    streaming_controller.h
    streaming_controller.cpp
)

add_subdirectory(LibAV)

target_link_libraries(StreamingController
    PRIVATE
    LibAV
    Qt6::Core
    Qt6::Gui
    Qt6::Multimedia
)
