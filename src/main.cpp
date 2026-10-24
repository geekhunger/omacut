// omacut — a dead-simple video length trimmer. Qt Quick (QML) UI, ffmpeg cuts.

#include <QApplication>
#include <QFileInfo>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>
#include <QFileOpenEvent>
#include <QTemporaryDir>
#include <functional>

#include "backend.h"
#include "clipmovekeys.h"
#include "shortcutsettings.h"
#include "thumbprovider.h"
#include "smoke.h"

class OmacutApplication : public QApplication {
public:
    using QApplication::QApplication;
    std::function<void(const QUrl &)> openFile;
    bool event(QEvent *event) override {
        if (event->type() == QEvent::FileOpen && openFile) {
            openFile(static_cast<QFileOpenEvent *>(event)->url());
            return true;
        }
        return QApplication::event(event);
    }
};

int main(int argc, char *argv[]) {
    // Qt's ffmpeg backend falls through to Vulkan video when VA-API is missing,
    // and on GPUs without Vulkan decode queues it then picks ffmpeg's hwaccel-only
    // av1 decoder and never falls back to dav1d, leaving the preview black. Stick
    // to the backends Qt checks codec support for, so software decode kicks in.
#ifdef Q_OS_LINUX
    if (!qEnvironmentVariableIsSet("QT_FFMPEG_DECODING_HW_DEVICE_TYPES"))
        qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "vaapi,cuda");
#endif

    OmacutApplication app(argc, argv);
    app.setApplicationName("omacut");
    app.setApplicationVersion("0.7.4");

    // Associates the window with omacut.desktop so the compositor (Wayland app_id
    // = this name) and taskbars pick up our installed icon.
    app.setDesktopFileName("omacut");
    app.setWindowIcon(QIcon::fromTheme("omacut"));

    // Modern, themeable controls (the same family Quickshell builds on).
    QQuickStyle::setStyle("Material");

    auto *provider = new ThumbProvider();
    Backend backend(provider, &app);

    const QStringList args = app.arguments();
    const bool smoke = args.contains(QStringLiteral("--smoke-test"));
    QTemporaryDir smokeSettings;
    ShortcutSettings shortcutStore(smoke ? smokeSettings.filePath("shortcuts.ini") : QString());
    QQmlApplicationEngine engine;

    // The engine takes ownership of the image provider.
    engine.addImageProvider("thumbs", provider);

    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("shortcutStore", &shortcutStore);

    if (smoke && args.contains(QStringLiteral("--smoke-hidden")))
        engine.setInitialProperties({{QStringLiteral("visible"), false}});
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
    if (smoke)
        startSmokeTest(backend, engine, args);
    else if (args.size() > 1)
        backend.load(QUrl::fromLocalFile(QFileInfo(args.at(1)).absoluteFilePath()));

    return app.exec();
}
