cmake_minimum_required(VERSION 3.21)
project(gst_rtmp_qml LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick)

# ===== Desktop (Linux/Windows/macOS) =====
if (NOT ANDROID)
  find_package(PkgConfig REQUIRED)
  # Need GStreamer core + video + GL; 1.22+ recommended
  pkg_check_modules(GST REQUIRED
    gstreamer-1.0>=1.22
    gstreamer-video-1.0
    gstreamer-gl-1.0
  )

  add_library(gst_rtmp_qml SHARED
    src/RtmpGstController.cpp
    src/RtmpGstController.h
  )

  target_include_directories(gst_rtmp_qml PRIVATE ${GST_INCLUDE_DIRS})
  target_compile_options(gst_rtmp_qml PRIVATE ${GST_CFLAGS_OTHER})
  target_link_libraries(gst_rtmp_qml PRIVATE Qt6::Quick ${GST_LIBRARIES})

  # Create a QML module plugin called "GstRtmp"
  qt_add_qml_module(gst_rtmp_qml
    URI GstRtmp
    VERSION 1.0
    QML_FILES src/RtmpVideo.qml
    # C++ types are auto-registered because they’re in this target
    # Add this if using QML_ELEMENT in header (not required here)
  )
endif()

# ===== Android =====
if (ANDROID)
  add_library(gst_rtmp_qml SHARED
    src/RtmpGstController.cpp
    src/RtmpGstController.h
  )

  qt_add_qml_module(gst_rtmp_qml
    URI GstRtmp
    VERSION 1.0
    QML_FILES src/RtmpVideo.qml
  )

  # Point this env var to the official GStreamer Android universal bundle
  set(GSTREAMER_ROOT_ANDROID "$ENV{GSTREAMER_ROOT_ANDROID}" CACHE PATH "GStreamer Android root")
  if (NOT EXISTS "${GSTREAMER_ROOT_ANDROID}")
    message(FATAL_ERROR "Set GSTREAMER_ROOT_ANDROID to the GStreamer Android bundle root")
  endif()

  set(GST_LIBDIR "${GSTREAMER_ROOT_ANDROID}/${ANDROID_ABI}/lib")
  set(GST_INCDIR "${GSTREAMER_ROOT_ANDROID}/${ANDROID_ABI}/include")

  add_library(gstreamer_android SHARED IMPORTED)
  set_target_properties(gstreamer_android PROPERTIES
    IMPORTED_LOCATION "${GST_LIBDIR}/libgstreamer_android.so"
  )

  target_include_directories(gst_rtmp_qml PRIVATE
    "${GST_INCDIR}/gstreamer-1.0"
    "${GST_INCDIR}/glib-2.0"
    "${GST_LIBDIR}/glib-2.0/include"
  )

  set(GST_CORE_LIBS
    "${GST_LIBDIR}/libgstreamer-1.0.so"
    "${GST_LIBDIR}/libgstbase-1.0.so"
    "${GST_LIBDIR}/libgstvideo-1.0.so"
    "${GST_LIBDIR}/libgstgl-1.0.so"
  )

  target_link_libraries(gst_rtmp_qml PRIVATE Qt6::Quick gstreamer_android ${GST_CORE_LIBS} log android)

  # Ensure required plugins are bundled into the APK
  set(ANDROID_EXTRA_LIBS
    ${GST_CORE_LIBS}
    "${GST_LIBDIR}/gstreamer-1.0/libgstqml6.so"
    "${GST_LIBDIR}/gstreamer-1.0/libgstplayback.so"
    "${GST_LIBDIR}/gstreamer-1.0/libgstgl.so"
    "${GST_LIBDIR}/gstreamer-1.0/libgstflv.so"
    "${GST_LIBDIR}/gstreamer-1.0/libgstrtmp2.so"
  )
  set_target_properties(gst_rtmp_qml PROPERTIES ANDROID_EXTRA_LIBS "${ANDROID_EXTRA_LIBS}")
endif()