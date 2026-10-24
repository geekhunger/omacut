QT += core gui quick quickcontrols2 multimedia testlib widgets
CONFIG += c++17 testcase
TARGET = backend_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += \
    ../src/shortcutsettings.h \
    ../src/clipmovekeys.h \
    ../src/backend.h \
    ../src/edit.h \
    ../src/ffmpeg.h \
    ../src/filepicker.h \
    ../src/thumbprovider.h \
    ../src/timeline.h \

SOURCES += \
    backend_tests.cpp \
    ../src/backend.cpp \
    ../src/edit.cpp \
    ../src/ffmpeg.cpp \
    ../src/thumbprovider.cpp \
    ../src/timeline.cpp \

macx {
    HEADERS += ../src/macfilepicker.h
    OBJECTIVE_SOURCES += ../src/macfilepicker.mm
    QMAKE_OBJECTIVE_CXXFLAGS += -fobjc-arc
    LIBS += -framework AppKit -framework UniformTypeIdentifiers
}

!win32 {
    QT += dbus
    HEADERS += ../src/portalfilepicker.h
    SOURCES += ../src/portalfilepicker.cpp
}
!macx {
    HEADERS += ../src/desktopfilepicker.h
    SOURCES += ../src/desktopfilepicker.cpp
}
