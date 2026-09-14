# Builds gnomarchy-bars.so: vendored hyprbars (vendor/, unmodified upstream
# except for the two documented hook lines in vendor/main.cpp - see
# ../VENDOR.md) plus our own drag-to-snap module (patch/). No cmake/meson
# dependency - hand-written, modeled on hyprbars' own upstream Makefile,
# since this machine already has everything a plain Makefile needs
# (g++/clang++, make, pkg-config, Hyprland headers).

ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wno-c++11-narrowing
INCLUDES = `pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon`
LIBS =

SRC = vendor/main.cpp vendor/barDeco.cpp vendor/BarPassElement.cpp patch/snap.cpp
TARGET = ./gnomarchy-bars.so

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) $(INCLUDES) $(SRC) -o $(TARGET) $(LIBS)

clean:
	rm -f ./gnomarchy-bars.so $(TARGET)

.PHONY: all clean
