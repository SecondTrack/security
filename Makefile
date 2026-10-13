# Theos-Makefile — baut Mesh Security als iOS-App (.app im .deb) für iPod touch 3G/4G (iOS 5.0–6.1, ARMv7).
# Voraussetzung: THEOS gesetzt + iOS-7.1-SDK unter $(THEOS)/sdks/iPhoneOS7.1.sdk.
#
# Zwei Programme:
#   MeshSecurity  die App (läuft als mobile, ändert nichts selbst)
#   msguard       setuid-root-Helfer im App-Bundle, die einzige Stelle mit root-Rechten
TARGET = iphone:clang:7.1:5.0
ARCHS  = armv7

# Standard ist das Paket zum Weitergeben. Debug-Pakete (make package FINALPACKAGE=0) loggen per NSLog.
FINALPACKAGE ?= 1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MeshSecurity

# Quellen: alle .m unter security/ (Schichten siehe docs/ARCHITECTURE.md).
SEC_DIRS             := $(shell find security -type d)
MeshSecurity_FILES    = $(shell find security -name '*.m' | sort)
MeshSecurity_FRAMEWORKS = UIKit CoreGraphics Foundation QuartzCore
MeshSecurity_CFLAGS   = -fobjc-arc -O2 -Wall
MeshSecurity_CFLAGS  += $(addprefix -I,$(SEC_DIRS))
MeshSecurity_CFLAGS  += -include security/Compat/MeshCompat.h
MeshSecurity_CFLAGS  += -DMESH_DEBUG_LOG=$(if $(filter 1,$(FINALPACKAGE)),0,1)

TOOL_NAME = msguard
msguard_FILES = helper/msguard.c
msguard_CFLAGS = -Wall -O2 -Isecurity/System -Ihelper/include
msguard_INSTALL_PATH = /Applications/MeshSecurity.app

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tool.mk
