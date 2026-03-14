cmake_minimum_required(VERSION 3.16)
project(wingout2 VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Use ccache if available
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    message(STATUS "Using ccache: ${CCACHE_PROGRAM}")
endif()

# Limit parallel compile jobs to avoid OOM (set JOB_POOL for large translation units)
set_property(GLOBAL PROPERTY JOB_POOLS compile_pool=2)
set(CMAKE_JOB_POOL_COMPILE compile_pool)

find_package(Qt6 6.7 REQUIRED COMPONENTS
    Bluetooth
    Quick
    QuickControls2
    Protobuf
    ProtobufQuick
    Grpc
    GrpcQuick
    ShaderTools
    Multimedia
    TextToSpeech
    Test
)

qt_standard_project_setup(REQUIRES 6.7)

qt_add_executable(wingout2
    src/main.cpp
    src/wingoutcontroller.h src/wingoutcontroller.cpp
    src/platformcontroller.h src/platformcontroller.cpp
    src/djicontroller.h src/djicontroller.cpp
    src/streamingsettingscontroller.h src/streamingsettingscontroller.cpp
)

qt_add_protobuf(wingout2_proto
    PROTO_FILES proto/wingout.proto
    QML
    QML_URI WingOut.Proto
)

qt_add_grpc(wingout2_grpc CLIENT
    PROTO_FILES proto/wingout.proto
    QML
    QML_URI WingOut.Grpc
)

# grpc client depends on proto message types
target_link_libraries(wingout2_grpc PUBLIC wingout2_proto)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(wingout2
    URI WingOut
    VERSION 2.0
    RESOURCES
        resources/fonts/MaterialSymbolsOutlined.ttf
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/components/GlassCard.qml
        qml/components/GlassButton.qml
        qml/components/GlassPanel.qml
        qml/components/StatusBadge.qml
        qml/components/MetricTile.qml
        qml/components/NavMenu.qml
        qml/components/SwipeLockOverlay.qml
        qml/components/SearchField.qml
        qml/components/VideoPlayerRTMP.qml
        qml/pages/DashboardPage.qml
        qml/pages/StatusPage.qml
        qml/pages/CamerasPage.qml
        qml/pages/DJIControlPage.qml
        qml/pages/ChatPage.qml
        qml/pages/PlayersPage.qml
        qml/pages/RestreamsPage.qml
        qml/pages/MonitorPage.qml
        qml/pages/ProfilesPage.qml
        qml/pages/LogsPage.qml
        qml/pages/SettingsPage.qml
        qml/pages/AVDPage.qml
        qml/dialogs/InitialSetup.qml
)

# Generated proto/grpc headers are in CMAKE_CURRENT_BINARY_DIR;
# src/ needed for QML type registration to find controller headers.
target_include_directories(wingout2 PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(wingout2 PRIVATE
    Qt6::Bluetooth
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Grpc
    Qt6::Multimedia
    Qt6::TextToSpeech
    wingout2_proto
    wingout2_grpc
)

# Android-specific settings
if(ANDROID)
    set_target_properties(wingout2 PROPERTIES
        QT_ANDROID_PACKAGE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android"
    )

    # Point Qt to our custom AndroidManifest.xml and Java sources
    set(QT_ANDROID_EXTRA_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/android/src/org/xaionaro/wingout2/MainActivity.java"
        "${CMAKE_CURRENT_SOURCE_DIR}/android/src/org/xaionaro/wingout2/WingOutDaemon.java"
        "${CMAKE_CURRENT_SOURCE_DIR}/android/src/org/xaionaro/wingout2/VibratorWrapper.java"
        "${CMAKE_CURRENT_SOURCE_DIR}/android/src/org/xaionaro/wingout2/WiFiHelper.java"
        "${CMAKE_CURRENT_SOURCE_DIR}/android/src/org/xaionaro/wingout2/SignalHelper.java"
    )

    # Link Android-specific libraries for JNI
    target_link_libraries(wingout2 PRIVATE android log)
endif()

# Tests
add_subdirectory(tests)
