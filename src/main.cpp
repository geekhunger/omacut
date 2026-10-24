// omacut — a dead-simple video length trimmer. Qt Quick (QML) UI, ffmpeg cuts.

#include <QGuiApplication>
#include <QFileInfo>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>
#include <QFileOpenEvent>
#include <functional>

#include "backend.h"
#include "clipmovekeys.h"
#include "shortcutsettings.h"
#include "thumbprovider.h"

class OmacutApplication : public QGuiApplication {
public:
    using QGuiApplication::QGuiApplication;
    std::function<void(const QUrl &)> openFile;
    bool event(QEvent *event) override {
        if (event->type() == QEvent::FileOpen && openFile) {
            openFile(static_cast<QFileOpenEvent *>(event)->url());
            return true;
        }
        return QGuiApplication::event(event);
    }
};

int main(int argc, char *argv[]) {
    // Qt's ffmpeg backend falls through to Vulkan video when VA-API is missing,
    // and on GPUs without Vulkan decode queues it then picks ffmpeg's hwaccel-only
    // av1 decoder and never falls back to dav1d, leaving the preview black. Stick
    // to the backends Qt checks codec support for, so software decode kicks in.
#ifndef Q_OS_MACOS
    if (!qEnvironmentVariableIsSet("QT_FFMPEG_DECODING_HW_DEVICE_TYPES"))
        qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "vaapi,cuda");
#endif

    OmacutApplication app(argc, argv);
    app.setApplicationName("omacut");
    app.setApplicationVersion("0.7.3");

    // Associates the window with omacut.desktop so the compositor (Wayland app_id
    // = this name) and taskbars pick up our installed icon.
    app.setDesktopFileName("omacut");
    app.setWindowIcon(QIcon::fromTheme("omacut"));

    // Modern, themeable controls (the same family Quickshell builds on).
    QQuickStyle::setStyle("Material");

    auto *provider = new ThumbProvider();
    Backend backend(provider, &app);

    ShortcutSettings shortcutStore;
    QQmlApplicationEngine engine;

    // The engine takes ownership of the image provider.
    engine.addImageProvider("thumbs", provider);

    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("shortcutStore", &shortcutStore);

    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return -1;
    new ClipMoveKeys(qobject_cast<QQuickWindow *>(engine.rootObjects().first()));

    app.openFile = [&engine](const QUrl &url) {
        // Use the existing drop workflow, preserving any current edit.
        QMetaObject::invokeMethod(engine.rootObjects().first(), "dropVideos",
                                  Q_ARG(QVariant, QVariant(QVariantList{url})));
    };

    // Optionally open a file passed on the command line.
    const QStringList args = app.arguments();
    if (args.size() > 1)
        backend.load(QUrl::fromLocalFile(QFileInfo(args.at(1)).absoluteFilePath()));

    return app.exec();
}
