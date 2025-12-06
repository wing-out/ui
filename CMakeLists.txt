cmake_minimum_required(VERSION 3.16)

project(wingout VERSION 0.1 LANGUAGES CXX)

#set(SANITIZER_FLAGS "-fsanitize=address -fsanitize-recover=address")
set(DEBUG_FLAGS "-fno-omit-frame-pointer -ggdb3")
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_COMPILER_LAUNCHER ccache)
set(CMAKE_CXX_COMPILER_LAUNCHER ccache)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${SANITIZER_FLAGS} ${DEBUG_FLAGS}")
set(CMAKE_LINKER_FLAGS "${CMAKE_LINKER_FLAGS} ${SANITIZER_FLAGS} ${DEBUG_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${SANITIZER_FLAGS} ${DEBUG_FLAGS}")

find_package(Qt6 REQUIRED COMPONENTS Bluetooth)
find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(Qt6 REQUIRED COMPONENTS Concurrent)
find_package(Qt6 REQUIRED COMPONENTS Connectivity)
find_package(Qt6 REQUIRED COMPONENTS Grpc)
find_package(Qt6 REQUIRED COMPONENTS GrpcTools)
find_package(Qt6 REQUIRED COMPONENTS GrpcQuick)
find_package(Qt6 REQUIRED COMPONENTS Multimedia)
find_package(Qt6 REQUIRED COMPONENTS Protobuf)
find_package(Qt6 REQUIRED COMPONENTS ProtobufTools)
find_package(Qt6 REQUIRED COMPONENTS ProtobufQuick)
find_package(Qt6 REQUIRED COMPONENTS Quick)
find_package(Qt6 REQUIRED COMPONENTS TextToSpeech)

qt_standard_project_setup(REQUIRES 6.9)

find_program(FONTFORGE_EXECUTABLE fontforge)
if(NOT FONTFORGE_EXECUTABLE)
    message(FATAL_ERROR "'fontforge' executable not found")
endif()

set(FONT FreeSans.ttf)
set(FONT_PATH ${CMAKE_CURRENT_BINARY_DIR}/FreeSans.ttf)

add_custom_command(
    OUTPUT ${FONT_PATH}
    COMMAND make -C ${CMAKE_CURRENT_SOURCE_DIR}/import/gnu-freefont/sfd ${FONT} && mv ${CMAKE_CURRENT_SOURCE_DIR}/import/gnu-freefont/sfd/${FONT} ${FONT_PATH}
    COMMENT "Generating FreeSans font"
)

add_custom_target(fonts ALL DEPENDS ${FONT_PATH})

set_source_files_properties(${FONT_PATH} PROPERTIES QT_RESOURCE_ALIAS fonts/FreeSans.ttf)

qt_add_executable(wingout
    main.cpp
)
add_dependencies(wingout fonts)

qt_add_qml_module(wingout
    URI WingOut
    VERSION 1.0
    QML_FILES
    Cameras.qml
    Dashboard.qml
    Main.qml
    ChatView.qml
    Settings.qml
    Timers.qml
    VideoPlayerRTMP.qml
    RESOURCES
    ${FONT_PATH}
    audio/chat_message_add.wav
    android/AndroidManifest.xml android/build.gradle android/res/values/libs.xml android/res/xml/qtprovider_paths.xml
)

qt_add_protobuf(DXProducer.ChatWebHook
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/streamctl/pkg/streamcontrol/protobuf/chat/chatwebhook.proto
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/streamcontrol/chat/
    QML
)

qt_add_protobuf(DXProducer.StreamControl
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/streamctl/pkg/streamcontrol/protobuf/streamcontrol.proto
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/streamcontrol/
    QML
)

add_dependencies(DXProducer.StreamControl
    DXProducer.ChatWebHook
)

qt_add_protobuf(DXProducer.Player
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/streamctl/pkg/streamd/grpc/player/player.proto
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/player/
    QML
)

qt_add_protobuf(DXProducer
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/streamctl/pkg/streamd/grpc/streamd.proto
    QML
)

target_sources(DXProducer
    PRIVATE
    dx_producer_client.h dx_producer_client.cpp
    image.h image.cpp
)

qt_add_grpc(DXProducer CLIENT
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/streamctl/pkg/streamd/grpc/streamd.proto
    QML
)

qt_add_protobuf(AVPipeline.LibAV
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/imports/avpipeline/protobuf/libav.proto
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/imports/avpipeline/protobuf/
    QML
)

qt_add_protobuf(AVPipeline
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/imports/avpipeline/protobuf/avpipeline.proto
    PROTO_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/imports/avpipeline/protobuf/
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/imports/avpipeline/protobuf/
    QML
)

qt_add_protobuf(FFStream
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/ffstream.proto
    PROTO_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/imports/avpipeline/protobuf/
    QML
)

target_sources(FFStream
    PRIVATE
    ffstream_client.h ffstream_client.cpp
)

qt_add_grpc(FFStream CLIENT
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/ffstream.proto
    PROTO_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/imports/avpipeline/protobuf/
    QML
)

qt_add_qml_module(Platform
    URI Platform
    VERSION 1.0
    SOURCES
    platform.h platform.cpp
    wifi_info.h wifi_info.cpp
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/Platform/
)

qt_add_qml_module(RemoteCameraController
    URI RemoteCameraController
    VERSION 1.0
    SOURCES
    ble_characteristic.h ble_remote_device.h ble_remote_device.cpp ble_service.h
    remote_camera_controller.h remote_camera_controller.cpp
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/RemoteCameraController/
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(wingout PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER center.dx.wingout
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
    QT_ANDROID_PACKAGE_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/android
)

target_link_libraries(RemoteCameraController
    PRIVATE
    Qt6::Bluetooth
    Qt6::Connectivity
)

target_link_libraries(DXProducer
    PRIVATE
    DXProducer.ChatWebHook
    DXProducer.StreamControl
    DXProducer.Player
    Qt6::Core
    Qt6::Quick
)

target_link_libraries(AVPipeline
    PRIVATE
    AVPipeline.LibAV
    Qt6::Core
    Qt6::Quick
)

target_link_libraries(FFStream
    PRIVATE
    AVPipeline.LibAV
    AVPipeline
    Qt6::Core
    Qt6::Quick
)

if(ANDROID)
    include(FetchContent)
    FetchContent_Declare(
        android_openssl
        URL https://github.com/KDAB/android_openssl/archive/refs/heads/master.zip
    )
    FetchContent_MakeAvailable(android_openssl)
    include(${android_openssl_SOURCE_DIR}/android_openssl.cmake)
    add_android_openssl_libraries(wingout)
endif()

target_link_libraries(wingout
    PRIVATE
    DXProducer.ChatWebHook
    DXProducer.StreamControl
    DXProducer.Player
    DXProducer
    AVPipeline.LibAV
    AVPipeline
    FFStream
    Platform
    RemoteCameraController
    Qt6::Core
    Qt6::CorePrivate
    Qt6::Concurrent
    Qt6::Quick
    Qt6::TextToSpeech
    Qt6::Network
)

include(GNUInstallDirs)
install(TARGETS wingout
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
