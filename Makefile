SHELL := /bin/bash

MIX_TARGET ?= rpi3
DEVICE ?=
WITH_ENV ?= ./scripts/with-env
SIGNED_FIRMWARE ?= _build/rpi3_dev/nerves/images/robine_wake-signed.fw
FWUP_PUBLIC_KEY ?= rootfs_overlay/etc/robine-wake/fwup-key.pub
IOS_DIR ?= ios/RobineWake
MOBILE_DIR ?= mobile
IPHONE_DERIVED_DATA ?= .derived/iphone
IPHONE_APP ?= $(IPHONE_DERIVED_DATA)/Build/Products/Debug-iphoneos/Robine Wake.app
EXPO_IPHONE_DERIVED_DATA ?= .derived/expo-iphone
EXPO_IPHONE_APP ?= $(EXPO_IPHONE_DERIVED_DATA)/Build/Products/Release-iphoneos/RobineWake.app
CHANGELOG ?=
BUILD_NUMBER ?=
DSP_DURATION ?= 60
DSP_VOLUME ?= 0.6
DSP_SEED ?= 0x524F4249
DSP_LAYER ?= rain
DSP_OUTPUT ?=
DSP_METRICS ?=
VERSION_CODE ?=
PLAY_TRACK ?=
PLAY_ARGS = $(if $(strip $(CHANGELOG)),changelog:"$(CHANGELOG)") $(if $(strip $(VERSION_CODE)),version_code:"$(VERSION_CODE)") $(if $(strip $(PLAY_TRACK)),track:"$(PLAY_TRACK)")
ANDROID_JAVA_HOME ?= $(shell /usr/libexec/java_home -v 17 2>/dev/null)
TESTFLIGHT_ARGS = $(if $(strip $(CHANGELOG)),changelog:"$(CHANGELOG)") $(if $(strip $(BUILD_NUMBER)),build_number:"$(BUILD_NUMBER)")
HOMEBREW_RUBY_PREFIX := $(shell brew --prefix ruby 2>/dev/null)
BUNDLE ?= $(if $(HOMEBREW_RUBY_PREFIX),$(HOMEBREW_RUBY_PREFIX)/bin/bundle,bundle)
PLATFORMIO ?= uvx --from platformio platformio

.PHONY: firmware burn-sd verify-firmware iphone testflight play-store android-bundle dsp button-build button-upload button-monitor expo-test expo-build expo-web expo-iphone

firmware:
	@$(WITH_ENV) env MIX_TARGET="$(MIX_TARGET)" mix deps.get
	@$(WITH_ENV) env MIX_TARGET="$(MIX_TARGET)" mix firmware

dsp:
	@command -v afplay >/dev/null 2>&1 || { echo "afplay is required (macOS only)" >&2; exit 1; }
	@set -e; \
	keep_output=0; \
	if [ -n "$(strip $(DSP_OUTPUT))" ]; then \
		dsp_file="$(DSP_OUTPUT)"; \
		keep_output=1; \
	else \
		dsp_file="$$(mktemp "$${TMPDIR:-/tmp}/robine-wake-dsp.XXXXXX.wav")"; \
	fi; \
	metrics_args=(); \
	if [ "$$keep_output" -eq 1 ]; then \
		metrics_file="$(strip $(DSP_METRICS))"; \
		if [ -z "$$metrics_file" ]; then metrics_file="$$dsp_file.metrics.json"; fi; \
		metrics_args=(--metrics "$$metrics_file"); \
	fi; \
	player_pid=""; \
	cleanup_dsp() { \
		if [ -n "$$player_pid" ]; then \
			kill -TERM "$$player_pid" 2>/dev/null || true; \
			wait "$$player_pid" 2>/dev/null || true; \
		fi; \
		if [ "$$keep_output" -eq 0 ] && [ -f "$$dsp_file" ]; then \
			unlink "$$dsp_file"; \
		fi; \
	}; \
	trap 'echo; echo "Lecture arrêtée."; cleanup_dsp; exit 0' INT; \
	trap 'cleanup_dsp; exit 143' TERM HUP; \
	trap 'cleanup_dsp' EXIT; \
	MIX_TARGET=host mix run --no-start scripts/play_meditation_dsp.exs -- \
		--duration "$(DSP_DURATION)" \
		--volume "$(DSP_VOLUME)" \
		--seed "$(DSP_SEED)" \
		--layer "$(DSP_LAYER)" \
		--output "$$dsp_file" \
		"$${metrics_args[@]}"; \
	echo "Lecture sur la sortie audio du Mac — Ctrl-C pour arrêter."; \
	afplay --volume "$(DSP_VOLUME)" "$$dsp_file" & \
	player_pid=$$!; \
	wait "$$player_pid"; \
	player_pid=""; \
	if [ "$$keep_output" -eq 1 ]; then echo "WAV conservé dans $$dsp_file"; fi

verify-firmware:
	@test -f "$(SIGNED_FIRMWARE)" || { echo "Missing signed firmware: $(SIGNED_FIRMWARE)" >&2; exit 1; }
	@fwup -V -p "$(FWUP_PUBLIC_KEY)" -i "$(SIGNED_FIRMWARE)"

burn-sd: verify-firmware
	@test -n "$(DEVICE)" || { echo "Usage: make burn-sd DEVICE=/dev/diskN" >&2; exit 1; }
	@device_info="$$(diskutil info "$(DEVICE)")"; \
	 echo "$$device_info" | grep -q "Device Location:.*External" || { echo "Refusing non-external disk: $(DEVICE)" >&2; exit 1; }; \
	 echo "$$device_info" | grep -q "Removable Media:.*Removable" || { echo "Refusing non-removable disk: $(DEVICE)" >&2; exit 1; }; \
	 echo "Writing $(SIGNED_FIRMWARE) to $(DEVICE)"; \
	 MIX_TARGET="$(MIX_TARGET)" mix burn --device "$(DEVICE)" --firmware "$(SIGNED_FIRMWARE)"

testflight:
	@$(WITH_ENV) bash -eu -o pipefail -c 'cd "$(IOS_DIR)" && "$(BUNDLE)" check >/dev/null 2>&1 || "$(BUNDLE)" install'
	@$(WITH_ENV) bash -eu -o pipefail -c 'cd "$(IOS_DIR)" && "$(BUNDLE)" exec fastlane ios beta $(TESTFLIGHT_ARGS)'

play-store:
	@$(WITH_ENV) bash -eu -o pipefail -c 'cd "$(MOBILE_DIR)" && "$(BUNDLE)" check >/dev/null 2>&1 || "$(BUNDLE)" install'
	@$(WITH_ENV) bash -eu -o pipefail -c 'export JAVA_HOME="$${JAVA_HOME_ANDROID:-$(ANDROID_JAVA_HOME)}"; cd "$(MOBILE_DIR)" && "$(BUNDLE)" exec fastlane android beta $(PLAY_ARGS)'

android-bundle:
	@$(WITH_ENV) bash -eu -o pipefail -c 'cd "$(MOBILE_DIR)" && "$(BUNDLE)" check >/dev/null 2>&1 || "$(BUNDLE)" install'
	@$(WITH_ENV) bash -eu -o pipefail -c 'export JAVA_HOME="$${JAVA_HOME_ANDROID:-$(ANDROID_JAVA_HOME)}"; cd "$(MOBILE_DIR)" && "$(BUNDLE)" exec fastlane android build $(if $(strip $(VERSION_CODE)),version_code:"$(VERSION_CODE)")'

iphone:
	@$(WITH_ENV) bash -eu -o pipefail -c ': "$${IPHONE_ID:?Set IPHONE_ID in .env}"; : "$${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"; cd "$(IOS_DIR)"; xcodegen generate; xcodebuild \
		-project RobineWake.xcodeproj \
		-scheme RobineWake \
		-configuration Debug \
		-destination "platform=iOS,id=$${IPHONE_ID}" \
		-derivedDataPath "$(IPHONE_DERIVED_DATA)" \
		DEVELOPMENT_TEAM="$${APPLE_TEAM_ID}" \
		-allowProvisioningUpdates \
		build; xcrun devicectl device install app --device "$${IPHONE_ID}" "$(IPHONE_APP)"'

expo-test:
	@cd "$(MOBILE_DIR)" && npm test
	@cd "$(MOBILE_DIR)" && npx expo-doctor

expo-build:
	@cd "$(MOBILE_DIR)" && npm run typecheck
	@cd "$(MOBILE_DIR)" && npx expo export --platform ios --output-dir dist/ios

expo-web:
	@cd "$(MOBILE_DIR)" && npm run web:export

expo-iphone:
	@$(WITH_ENV) bash -eu -o pipefail -c ': "$${IPHONE_ID:?Set IPHONE_ID in .env}"; : "$${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"; cd "$(MOBILE_DIR)"; npm run typecheck; npx expo prebuild --clean --platform ios; xcodebuild \
		-workspace ios/RobineWake.xcworkspace \
		-scheme RobineWake \
		-configuration Release \
		-destination "platform=iOS,id=$${IPHONE_ID}" \
		-derivedDataPath "../$(EXPO_IPHONE_DERIVED_DATA)" \
		DEVELOPMENT_TEAM="$${APPLE_TEAM_ID}" \
		-allowProvisioningUpdates \
		build; cd ..; xcrun devicectl device install app \
		--device "$${IPHONE_ID}" \
		--timeout 300 \
		"$(EXPO_IPHONE_APP)"; xcrun devicectl device process launch \
		--device "$${IPHONE_ID}" \
		--timeout 300 \
		fr.robine.wake'

button-build:
	$(WITH_ENV) $(PLATFORMIO) run --project-dir hardware/remote_button

button-upload:
	@test -n "$(PORT)" || { echo "PORT is required (example: make button-upload PORT=/dev/cu.usbmodem1234)" >&2; exit 1; }
	$(WITH_ENV) $(PLATFORMIO) run --project-dir hardware/remote_button --target upload --upload-port "$(PORT)"

button-monitor:
	@test -n "$(PORT)" || { echo "PORT is required (example: make button-monitor PORT=/dev/cu.usbmodem1234)" >&2; exit 1; }
	$(WITH_ENV) $(PLATFORMIO) device monitor --project-dir hardware/remote_button --port "$(PORT)" --baud 115200
