

find_package(Qt6 REQUIRED COMPONENTS Core Qml)

qt_add_library(StreamingSettingsController STATIC)

qt_add_qml_module(StreamingSettingsController
    URI StreamingSettingsController
    VERSION 1.0
    SOURCES
        streaming_settings_controller.h
        streaming_settings_controller.cpp
)

target_link_libraries(StreamingSettingsController
    PRIVATE
        Qt6::Core
        Qt6::Qml
)
