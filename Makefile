.PHONY: all backend frontend test test-go test-qml test-e2e-headless test-e2e test-android-e2e clean proto \
	apk-arm64 apk-x86_64 apk-all wingoutd-android-arm64 wingoutd-android-x86_64

BUILD_DIR := build
PROTO_DIR := proto
GO_BIN := $(BUILD_DIR)/wingoutd
QT_BUILD_DIR := $(BUILD_DIR)/frontend
GO_TAGS := -tags with_libav,with_libsrt

# Qt / Android SDK paths
QT_DIR := $(HOME)/Qt/6.10.1
QT_HOST_PATH := $(QT_DIR)/gcc_64
ANDROID_SDK_ROOT := $(HOME)/Android/Sdk
ANDROID_NDK_ROOT := $(ANDROID_SDK_ROOT)/ndk/28.0.13004108
ANDROID_PLATFORM := android-28
BUILD_TOOLS := $(ANDROID_SDK_ROOT)/build-tools/35.0.0
DEBUG_KEYSTORE := $(HOME)/.android/debug.keystore

# Android build directories
ANDROID_BUILD_ARM64 := /tmp/wingout2-build-arm64
ANDROID_BUILD_X86_64 := /tmp/wingout2-build-x86_64

all: backend frontend

# --- Go Backend ---

backend:
	go build $(GO_TAGS) -o $(GO_BIN) ./cmd/wingoutd/

# Cross-compile wingoutd for Android ARM64
wingoutd-android-arm64:
	GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="-s -w" \
		-o $(ANDROID_BUILD_ARM64)/android-build/libs/arm64-v8a/libwingoutd.so \
		./cmd/wingoutd/

# Cross-compile wingoutd for Android x86_64 (requires NDK clang for CGO)
wingoutd-android-x86_64:
	CC=$(ANDROID_NDK_ROOT)/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android28-clang \
	GOOS=android GOARCH=amd64 CGO_ENABLED=1 go build -ldflags="-s -w" \
		-o $(ANDROID_BUILD_X86_64)/android-build/libs/x86_64/libwingoutd.so \
		./cmd/wingoutd/

proto:
	protoc \
		--go_out=pkg/api --go_opt=paths=source_relative \
		--go-grpc_out=pkg/api --go-grpc_opt=paths=source_relative \
		-I$(PROTO_DIR) $(PROTO_DIR)/wingout.proto

# --- Qt Frontend (desktop) ---

frontend:
	cmake -B $(QT_BUILD_DIR) -S . -DCMAKE_PREFIX_PATH=$(QT_HOST_PATH) \
		&& cmake --build $(QT_BUILD_DIR)

# --- Android APKs ---

# Build type: Release (default) or Debug
BUILD_TYPE ?= Release

# Internal: configure + build + sign for a given ABI
# Usage: $(call build_apk,<qt_abi_dir>,<build_dir>,<output_apk>,<wingoutd_target>)
define build_apk
	cmake -B $(2) -S . \
		-DCMAKE_TOOLCHAIN_FILE=$(QT_DIR)/$(1)/lib/cmake/Qt6/qt.toolchain.cmake \
		-DQT_HOST_PATH=$(QT_HOST_PATH) \
		-DANDROID_SDK_ROOT=$(ANDROID_SDK_ROOT) \
		-DANDROID_NDK_ROOT=$(ANDROID_NDK_ROOT) \
		-DANDROID_PLATFORM=$(ANDROID_PLATFORM) \
		-DCMAKE_BUILD_TYPE=$(BUILD_TYPE)
	@# Build wingoutd for this ABI and place in native libs dir
	$(MAKE) $(3)
	@# Clear stale Gradle native lib caches
	@rm -rf $(2)/android-build/build/intermediates/stripped_native_libs $(2)/android-build/build/intermediates/merged_native_libs
	@# Build APK via androiddeployqt + Gradle
	$(MAKE) -C $(2) apk
	@if [ "$(BUILD_TYPE)" = "Debug" ]; then \
		cp $(2)/android-build/build/outputs/apk/debug/android-build-debug.apk $(4); \
	else \
		$(BUILD_TOOLS)/zipalign -f 4 $(2)/android-build/wingout2.apk $(2)/wingout2-aligned.apk; \
		$(BUILD_TOOLS)/apksigner sign \
			--ks $(DEBUG_KEYSTORE) --ks-pass pass:android \
			--out $(4) $(2)/wingout2-aligned.apk; \
	fi
	@echo "APK ready: $(4)"
endef

apk-arm64:
	$(call build_apk,android_arm64_v8a,$(ANDROID_BUILD_ARM64),wingoutd-android-arm64,/tmp/wingout2-arm64.apk)

apk-x86_64:
	$(call build_apk,android_x86_64,$(ANDROID_BUILD_X86_64),wingoutd-android-x86_64,/tmp/wingout2-x86_64.apk)

apk-all: apk-arm64 apk-x86_64

# --- Tests ---

test: test-go test-qml

test-go:
	go test $(GO_TAGS) -count=1 -race ./pkg/...

test-go-coverage:
	go test $(GO_TAGS) -count=1 -race -coverprofile=coverage.out ./pkg/...
	go tool cover -func=coverage.out

test-qml: frontend
	cd $(QT_BUILD_DIR) && QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
		ctest --output-on-failure -R tst_wingout

test-e2e-headless:
	go test $(GO_TAGS),test_e2e -count=1 -run TestHeadless -v ./tests/e2e/

test-e2e:
	go test $(GO_TAGS),test_e2e -count=1 -run TestFull -v ./tests/e2e/

test-android-e2e:
	go test -tags android_e2e -count=1 -v -timeout 30m ./tests/e2e/android/

# --- Cleanup ---

clean:
	rm -rf $(BUILD_DIR) coverage.out
