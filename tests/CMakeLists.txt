find_package(Qt6 REQUIRED COMPONENTS QuickTest Test Quick Qml)

# All add_test names beginning with `tst_` are picked up by
# scripts/run_headless_tests.sh via `ctest -R '^tst_'`. To opt a test out
# (e.g. fixture-pending or known-disabled), use:
#   set_tests_properties(<name> PROPERTIES DISABLED TRUE)
# rather than renaming. Renaming outside the tst_* convention loses the
# discoverability benefit.

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
#
# QML_XHR_ALLOW_FILE_READ=1 enables XMLHttpRequest GET on file:// URLs,
# which is disabled by default in Qt. The grep-style source assertion
# in tst_cameras_builtin_activation_lifecycle.qml's
# test_13_every_async_callsite_uses_withEpoch_wrapper depends on this
# to read CamerasBuiltin.qml from disk. Limited to the test binary —
# the production app does not enable this flag.
add_test(NAME tst_wingout COMMAND tst_wingout)
set_tests_properties(tst_wingout PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;LD_LIBRARY_PATH=${Qt6_DIR}/../..;QML_XHR_ALLOW_FILE_READ=1"
)

# ---------------------------------------------------------------------------
# C++ unit test for StreamingSettingsController m_active reconciliation.
# Standalone QtTest binary — does not need the Quick/QML stack.
# ---------------------------------------------------------------------------
qt_add_executable(tst_streaming_settings_controller_reconcile
    tst_streaming_settings_controller_reconcile.cpp
)

target_include_directories(tst_streaming_settings_controller_reconcile PRIVATE
    ${CMAKE_SOURCE_DIR}/StreamingSettingsController
)

target_link_libraries(tst_streaming_settings_controller_reconcile
    PRIVATE
    StreamingSettingsController
    Qt6::Test
    Qt6::Core
    Qt6::Qml
)

add_test(NAME tst_streaming_settings_controller_reconcile
    COMMAND tst_streaming_settings_controller_reconcile)
set_tests_properties(tst_streaming_settings_controller_reconcile PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;LD_LIBRARY_PATH=${Qt6_DIR}/../.."
)

# ---------------------------------------------------------------------------
# QML wrapper-pattern enforcement (aa4c816 follow-up).
#
# QtProtobuf's auto-generated `Q_INVOKABLE void <RpcName>(const Request&, ...)`
# methods cannot be invoked from QML with a `{}` literal — the C++ binding
# rejects the JS-object→protobuf coercion at runtime, manifesting as a 50-min
# bisect window between 96a22f0 (which started calling it) and aa4c816 (which
# added the camelCase wrapper). To prevent regressions, every QML caller must
# go through a Q_INVOKABLE wrapper in ffstream_client.h that takes primitive
# args and constructs the proto in C++.
#
# This test greps every .qml file for direct calls to PascalCase RPC methods
# on the ffstream client and fails the build if any are present. The forbidden
# list is auto-derived from the generated qmlffstream_client.grpc.qpb.h when
# available, otherwise falls back to the known wrapper roster as of d8c7ef0.
# ---------------------------------------------------------------------------
add_test(NAME tst_qml_wrapper_pattern
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/check_qml_proto_wrappers.sh
            ${CMAKE_SOURCE_DIR}
            ${CMAKE_BINARY_DIR}/qmlffstream_client.grpc.qpb.h
)
