cmake_minimum_required(VERSION 3.16)

# Prefer the NEW behavior for CMP0135 (DOWNLOAD_EXTRACT_TIMESTAMP) so
# extracted files get current timestamps and fetched content changes
# trigger rebuilds.
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

project(wingout VERSION 0.1 LANGUAGES CXX)


#set(SANITIZER_FLAGS "-fsanitize=address -fsanitize-recover=address")
set(DEBUG_FLAGS "-fno-omit-frame-pointer -ggdb3 -gsplit-dwarf")
# Generate qmlls.ini for IDE/QML language server support on desktop only.
# Scanning all QML files for qmlls can produce import-resolution warnings when
# desktop-only QML (QtQuick.Studio, QStream, etc.) are present but not
# available on Android. Disable qmlls generation for Android builds to avoid
# spurious warnings and exclude desktop-only QML from the Android package
# below.
if(NOT ANDROID)
    set(QT_QML_GENERATE_QMLLS_INI ON)
else()
    set(QT_QML_GENERATE_QMLLS_INI OFF)
endif()
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_UNITY_BUILD ON)
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
endif()
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${SANITIZER_FLAGS} ${DEBUG_FLAGS}")
set(CMAKE_LINKER_FLAGS "${CMAKE_LINKER_FLAGS} ${SANITIZER_FLAGS} ${DEBUG_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${SANITIZER_FLAGS} ${DEBUG_FLAGS}")
set(QT_NO_PRIVATE_MODULE_WARNING ON)
if(ANDROID)
    set(QT_ANDROID_BUILD_ALL_ABIS ON)
    set(QT_ANDROID_ABIS arm64-v8a)
    set(CMAKE_ANDROID_SDK $ENV{ANDROID_SDK_ROOT})
    set(CMAKE_ANDROID_NDK $ENV{ANDROID_NDK_ROOT})
    set(CMAKE_ANDROID_STL_TYPE c++_shared)
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        set(QT_ANDROID_SIGN_APK ON)
    endif()
endif()

find_package(Qt6 REQUIRED COMPONENTS
    Bluetooth
    Core
    CorePrivate
    Concurrent
    Network
    Gui
    Grpc
    GrpcTools
    GrpcQuick
    Multimedia
    Protobuf
    ProtobufTools
    ProtobufQuick
    Quick
    Qml
    TextToSpeech
    Test
)


qt_standard_project_setup(REQUIRES 6.8)

find_program(FONTFORGE_EXECUTABLE fontforge)
if(NOT FONTFORGE_EXECUTABLE)
    message(FATAL_ERROR "'fontforge' executable not found")
endif()

set(FONT FreeSans.ttf)
set(FONT_PATH ${CMAKE_CURRENT_BINARY_DIR}/FreeSans.ttf)

add_custom_command(
    OUTPUT ${FONT_PATH}
    # Use helper script which attempts to reuse existing builds, copy a system
    # font when available, or fall back to generating the font. This is more
    # robust than invoking make directly (fontforge generation may fail on
    # some environments).
    COMMAND ${CMAKE_COMMAND} -E env "FONT_PATH=${FONT_PATH}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/copy_or_generate_font.sh" ${FONT_PATH}
    COMMENT "Generating or copying FreeSans font"
)

add_custom_target(fonts ALL DEPENDS ${FONT_PATH})

set_source_files_properties(${FONT_PATH} PROPERTIES QT_RESOURCE_ALIAS fonts/FreeSans.ttf)

qt_add_executable(wingout
    main.cpp
)
add_dependencies(wingout fonts)

## Explicitly list QML files for the WingOut module. This makes it easy to
## remove desktop-only QML from the Android build (see WINGOUT_DESKTOP_QML
## below).
set(WINGOUT_QML_FILES
    Application.qml
    InitialSetup.qml
    Cameras.qml
    CamerasBuiltin.qml
    Chat.qml
    ChatView.qml
    Dashboard.qml
    DJIControl.qml
    Main.qml
    Monitor.qml
    Players.qml
    Profiles.qml
    Restreams.qml
    Settings.qml
    SwipeLockOverlay.qml
    Timers.qml
    VideoPlayerRTMP.qml
)

## Desktop-only QML (QtQuick.Studio, QStream, etc.) that should not be
## included when building for Android. Keep this list focused — add more
## entries here if the QML compiler warns about other desktop-only imports.
set(WINGOUT_DESKTOP_QML
    import/streamctl/pkg/experimental/qstreampanel/qml/QStream/EventListSimulator.qml
    import/streamctl/pkg/experimental/qstreampanel/qml/QStream/EventListModel.qml
    import/streamctl/pkg/experimental/qstreampanel/qml/QStream/DirectoryFontLoader.qml
    import/streamctl/pkg/experimental/qstreampanel/qml/QStream/Constants.qml
    import/streamctl/pkg/experimental/qstreampanel/qml/QStreamContent/Controls.ui.qml
    import/streamctl/pkg/experimental/qstreampanel/qml/QStreamContent/App.qml
    import/streamctl/pkg/experimental/qstreampanel/qml/QStreamContent/Monitor.ui.qml
    import/streamctl/pkg/experimental/qstreampanel/qml/QStreamContent/ListViewStyled.qml
    import/streamctl/pkg/experimental/qstreampanel/qml/QStreamContent/Borders.qml
)

if(ANDROID)
    foreach(_f IN LISTS WINGOUT_DESKTOP_QML)
        list(REMOVE_ITEM WINGOUT_QML_FILES ${_f})
    endforeach()
endif()

qt_add_qml_module(wingout
    URI WingOut
    VERSION 1.0
    QML_FILES
    ${WINGOUT_QML_FILES}
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
    ${CMAKE_CURRENT_SOURCE_DIR}/import/player/pkg/player/protobuf/player.proto
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
    ${CMAKE_CURRENT_SOURCE_DIR}/import/avpipeline/protobuf/libav.proto
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/imports/avpipeline/protobuf/
    QML
)

qt_add_protobuf(AVPipeline
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/avpipeline/protobuf/avpipeline.proto
    PROTO_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/avpipeline/protobuf/
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/imports/avpipeline/protobuf/
    QML
)

qt_add_protobuf(FFStream
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/ffstream.proto
    PROTO_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/
    ${CMAKE_CURRENT_SOURCE_DIR}/import/avpipeline/protobuf/
    QML
)

qt_add_protobuf(WingOutDiagnostics
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/protobuf/diagnostics.proto
    QML
)

target_sources(FFStream
    PRIVATE
    ffstream_client.h ffstream_client.cpp
)

target_link_libraries(FFStream
    PRIVATE
    WingOutDiagnostics
)

qt_add_grpc(FFStream CLIENT
    PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/ffstream.proto
    PROTO_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}/import/ffstream/pkg/ffstreamserver/grpc/
    ${CMAKE_CURRENT_SOURCE_DIR}/import/avpipeline/protobuf/
    QML
)

qt_add_qml_module(Platform
    URI Platform
    VERSION 1.0
    SOURCES
    platform.h platform.cpp
    wifi_info.h wifi_info.cpp
    channel_quality_info.h channel_quality_info.cpp
    OUTPUT_DIRECTORY
    ${CMAKE_CURRENT_BINARY_DIR}/Platform/
)

target_link_libraries(Platform
    PRIVATE
    Qt6::Core
    Qt6::Qml
    Qt6::CorePrivate
)

#add_subdirectory(StreamingController)
add_subdirectory(StreamingSettingsController)
add_subdirectory(import/libdji libdji)

qt_add_qml_module(RemoteCameraController
    URI RemoteCameraController
    VERSION 1.0
    SOURCES
    ble_characteristic.h ble_remote_device.h ble_remote_device.cpp ble_service.h
    remote_camera_controller.h remote_camera_controller.cpp
    dji_controller.h dji_controller.cpp
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
    Qt6::Core
    Qt6::Qml
    Qt6::Bluetooth
    dji
    # Qt6::Connectivity
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
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
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
    StreamingSettingsController
    RemoteCameraController
    Qt6::Core
    Qt6::CorePrivate
    Qt6::Concurrent
    Qt6::Quick
    Qt6::TextToSpeech
    Qt6::Network
    Qt6::Multimedia
)

target_precompile_headers(wingout PRIVATE
    <QtCore/QtCore>
    <QtGui/QtGui>
    <QtQuick/QtQuick>
    <QtQml/QtQml>
    <QtNetwork/QtNetwork>
)

include(GNUInstallDirs)
install(TARGETS wingout
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
