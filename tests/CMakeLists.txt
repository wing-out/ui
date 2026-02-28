if(ANDROID)
    return()
endif()

find_package(Qt6 REQUIRED COMPONENTS QuickTest Multimedia TextToSpeech)

qt_add_executable(tst_wingout
    tst_wingout.cpp
    mock_platform.h
    mock_backend.h
)

# Make QML test files available
qt_add_resources(tst_wingout "qml_tests"
    PREFIX "/tst"
    FILES
        qml/tst_glass_components.qml
        qml/tst_metric_tile.qml
        qml/tst_navigation.qml
        qml/tst_initial_setup.qml
        qml/tst_settings_page.qml
        qml/tst_dashboard_logic.qml
        qml/tst_chat_view.qml
        qml/tst_profiles_page.qml
        qml/tst_cameras_page.qml
        qml/tst_restreams_page.qml
)

# Embed WingOut QML module resources so the test binary can resolve
# types from qrc (the main module's qmldir uses "prefer :/qt/qml/WingOut/").
set_target_properties(tst_wingout PROPERTIES AUTORCC ON)
target_sources(tst_wingout PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/wingout_qml.qrc
)

target_link_libraries(tst_wingout PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickTest
    Qt6::Test
    Qt6::Qml
    Qt6::Multimedia
    Qt6::TextToSpeech
)

# Tell QtQuickTest where to find test QML files
target_compile_definitions(tst_wingout PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
)

add_test(NAME tst_wingout
    COMMAND tst_wingout
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

set_tests_properties(tst_wingout PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}"
)
