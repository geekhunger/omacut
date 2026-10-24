QT += core gui qml quick quickcontrols2 multimedia widgets

CONFIG += c++17 release
TARGET = omacut
TEMPLATE = app

HEADERS += \
    src/smoke.h \
    src/shortcutsettings.h \
    src/clipmovekeys.h \
    src/filepicker.h \
    src/edit.h \
    src/ffmpeg.h \
    src/thumbprovider.h \
    src/timeline.h \
    src/backend.h

SOURCES += \
    src/smoke.cpp \
    src/main.cpp \
    src/edit.cpp \
    src/ffmpeg.cpp \
    src/thumbprovider.cpp \
    src/timeline.cpp \
    src/backend.cpp

RESOURCES += src/resources.qrc

macx {
    QMAKE_MACOSX_DEPLOYMENT_TARGET = 26.0
    HEADERS += src/macfilepicker.h
    OBJECTIVE_SOURCES += src/macfilepicker.mm
    QMAKE_OBJECTIVE_CXXFLAGS += -fobjc-arc
    LIBS += -framework AppKit -framework UniformTypeIdentifiers
    ICON = packaging/Omacut.icns
    QMAKE_INFO_PLIST = packaging/Info.plist
}

!win32 {
    QT += dbus
    HEADERS += src/portalfilepicker.h
    SOURCES += src/portalfilepicker.cpp
}
!macx {
    HEADERS += src/desktopfilepicker.h
    SOURCES += src/desktopfilepicker.cpp
}
