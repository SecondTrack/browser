# Browser — sicherer Lese-Browser für iPod touch 4 (iOS 6.1, ARMv7), Theos.
# Eigene Darstellung (CoreText), kein JavaScript, TLS 1.2/1.3 via mbedTLS mit Zertifikatsprüfung.
TARGET = iphone:clang:7.1:6.0
ARCHS  = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Browser

Browser_FILES  = $(wildcard src/*.m)
Browser_FRAMEWORKS = UIKit CoreGraphics CoreText QuartzCore Foundation
Browser_CFLAGS  = -fobjc-arc -O2 -Wall -Isrc -Ivendor/mbedtls/include
Browser_LDFLAGS = -Lvendor/mbedtls/lib
Browser_LIBRARIES = mbedtls mbedx509 mbedcrypto

include $(THEOS_MAKE_PATH)/application.mk
