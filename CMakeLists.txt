cmake_minimum_required(VERSION 3.16)

project(wingout VERSION 0.1 LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_COMPILER_LAUNCHER ccache)
set(CMAKE_CXX_COMPILER_LAUNCHER ccache)

find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(Qt6 REQUIRED COMPONENTS Concurrent)
find_package(Qt6 REQUIRED COMPONENTS Grpc)
find_package(Qt6 REQUIRED COMPONENTS GrpcTools)
find_package(Qt6 REQUIRED COMPONENTS GrpcQuick)
find_package(Qt6 REQUIRED COMPONENTS Multimedia)
find_package(Qt6 REQUIRED COMPONENTS Protobuf)
find_package(Qt6 REQUIRED COMPONENTS ProtobufTools)
find_package(Qt6 REQUIRED COMPONENTS ProtobufQuick)
find_package(Qt6 REQUIRED COMPONENTS Quick)
find_package(Qt6 REQUIRED COMPONENTS TextToSpeech)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(wingout
    main.cpp
)

qt_add_qml_module(wingout
    URI WingOut
    VERSION 1.0
    QML_FILES
        Main.qml
        ChatView.qml
        Timers.qml
        VideoPlayerRTMP.qml
    RESOURCES
        audio/chat_message_add.wav
        android/AndroidManifest.xml android/build.gradle android/res/values/libs.xml android/res/xml/qtprovider_paths.xml
)

qt_add_protobuf(DXProducer.Player
    PROTO_FILES
        ./import/streamctl/pkg/streamd/grpc/player/player.proto
    OUTPUT_DIRECTORY
        ${CMAKE_CURRENT_BINARY_DIR}/player/
    QML
)

qt_add_grpc(DXProducer.Player CLIENT
    PROTO_FILES
        ./import/streamctl/pkg/streamd/grpc/player/player.proto
    OUTPUT_DIRECTORY
        ${CMAKE_CURRENT_BINARY_DIR}/player/
    QML
)

qt_add_protobuf(DXProducer
    PROTO_FILES
        ./import/streamctl/pkg/streamd/grpc/streamd.proto
    QML
)

target_sources(DXProducer
  PRIVATE
    dx_producer_client.h dx_producer_client.cpp
    image.h image.cpp
)

qt_add_grpc(DXProducer CLIENT
    PROTO_FILES
        ./import/streamctl/pkg/streamd/grpc/streamd.proto
    QML
)

qt_add_qml_module(Platform
    URI Platform
    VERSION 1.0
    SOURCES
        platform.h platform.cpp
    OUTPUT_DIRECTORY
        ${CMAKE_CURRENT_BINARY_DIR}/Platform/
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

target_link_libraries(DXProducer
    PRIVATE
    DXProducer.Player
    Qt6::Core
    Qt6::Quick
)

target_link_libraries(wingout
    PRIVATE
    DXProducer.Player
    DXProducer
    Platform
    Qt6::Core
    Qt6::CorePrivate
    Qt6::Concurrent
    Qt6::Quick
    Qt6::TextToSpeech
)

include(GNUInstallDirs)
install(TARGETS wingout
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
