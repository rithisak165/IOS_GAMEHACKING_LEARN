TARGET := iphone:clang:latest:16.0
ARCHS := arm64 
DEBUG := 0
FINALPACKAGE := 1
FOR_RELEASE := 1
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ipa

# Core Frameworks (Pure standalone Apple frameworks - no CydiaSubstrate dependency required for jailed sideloading)
ipa_FRAMEWORKS = UIKit Foundation Security QuartzCore CoreGraphics CoreText AVFoundation Accelerate GLKit SystemConfiguration GameController

# Base compilation flags
COMMON_FLAGS = -std=c++17 -fno-rtti -fno-exceptions -DNDEBUG -fvisibility=hidden -w

# Hikari OLLVM Obfuscation Flags (Control Flow Flattening + Bogus Control Flow + String Encryption + Instruction Substitution)
ifeq ($(HIKARI),1)
  HIKARI_OLLVM_FLAGS = -mllvm -enable-cffobf -mllvm -enable-bcfobf -mllvm -enable-strcry -mllvm -enable-subobf
else
  HIKARI_OLLVM_FLAGS =
endif

# Core source files (protected with Hikari OLLVM)
ipa_CCFLAGS = $(COMMON_FLAGS) $(HIKARI_OLLVM_FLAGS)
ipa_CFLAGS = -fobjc-arc $(HIKARI_OLLVM_FLAGS) -w

# Source files list
ipa_FILES = ImGuiDrawView.xm $(wildcard Esp/*.mm) $(wildcard Esp/*.m) $(wildcard KittyMemory/*.cpp) $(wildcard KittyMemory/*.mm) $(wildcard IMGUI/*.cpp) $(wildcard IMGUI/*.mm)

# CRITICAL RULE: Exclude ImGui from Hikari OLLVM to prevent slider crashes and frame drops
# Override flags specifically for IMGUI source files so they compile clean and native at -O3
IMGUI_SRCS = $(wildcard IMGUI/*.cpp) $(wildcard IMGUI/*.mm)
$(foreach src,$(IMGUI_SRCS),$(eval ipa_CCFLAGS_$(src) = -std=c++17 -O3 -fno-rtti -fno-exceptions -w))
$(foreach src,$(IMGUI_SRCS),$(eval ipa_CFLAGS_$(src) = -fobjc-arc -O3 -w))
$(foreach src,$(IMGUI_SRCS),$(eval $(src)_CCFLAGS = -std=c++17 -O3 -fno-rtti -fno-exceptions -w))
$(foreach src,$(IMGUI_SRCS),$(eval $(src)_CFLAGS = -fobjc-arc -O3 -w))

ipa_LDFLAGS += -lz -stdlib=libc++

include $(THEOS_MAKE_PATH)/tweak.mk
