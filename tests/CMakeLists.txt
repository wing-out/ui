find_package(Qt6 REQUIRED COMPONENTS QuickTest Test Quick Qml)

# ---------------------------------------------------------------------------
# Test executable – uses QUICK_TEST_MAIN_WITH_SETUP to run every tst_*.qml
# file found under the qml/ subdirectory.
# ---------------------------------------------------------------------------
qt_add_executable(tst_wingout
    tst_wingout.cpp
    mock_platform.h mock_platform.cpp
)

target_compile_definitions(tst_wingout PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    WINGOUT_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
    WINGOUT_BUILD_DIR="${CMAKE_BINARY_DIR}"
)

target_link_libraries(tst_wingout
    PRIVATE
    wingout_qml
    wingout_qmlplugin
    wingout_qmlplugin_init
    Qt6::QuickTest
    Qt6::Test
    Qt6::Quick
    Qt6::Qml
)

# Tell the QML import scanner where to find the WingOut module's qmldir.
# The wingout_qml module places its qmldir in CMAKE_BINARY_DIR (the build
# root) so we need that on the import path for qt_import_qml_plugins to
# discover it, and for the runtime QML engine fallback.
set_target_properties(tst_wingout PROPERTIES
    QT_QML_IMPORT_PATH "${CMAKE_BINARY_DIR}"
)

# Ensure all static QML module plugins are linked into the test binary so
# that "import WingOut", "import Platform 1.0", etc. resolve at runtime.
qt_import_qml_plugins(tst_wingout)

# The shared QML module plugins (Platform, DXProducer, FFStream, etc.) must
# be built so that "import streamd", "import Platform 1.0", etc. can be
# resolved at runtime via the import path.
if(TARGET qt_internal_plugins)
    add_dependencies(tst_wingout qt_internal_plugins)
endif()

# Register the test with CTest and request headless execution.
add_test(NAME tst_wingout COMMAND tst_wingout)
set_tests_properties(tst_wingout PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;LD_LIBRARY_PATH=${Qt6_DIR}/../.."
)
