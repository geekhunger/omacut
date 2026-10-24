#include "smoke.h"
#include "backend.h"
#include "ffmpeg.h"
#include <QCoreApplication>
#include <QDebug>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMediaPlayer>
#include <QQmlApplicationEngine>
#include <QSaveFile>
#include <QTimer>
#include <QVideoFrame>
#include <QVideoSink>
#include <cmath>
#include <memory>

namespace {
QString option(const QStringList &args, const QString &name) {
    const int i = args.indexOf(name);
    return i >= 0 && i + 1 < args.size() ? QFileInfo(args.at(i + 1)).absoluteFilePath() : QString();
}
struct State {
    QString input, output, report;
    QJsonObject result;
    bool finished = false, loaded = false, preview = false, exporting = false;
    double expectedDuration = 0;
};
}

void startSmokeTest(Backend &backend, QQmlApplicationEngine &engine, const QStringList &args) {
    auto s = std::make_shared<State>();
    s->input = option(args, "--smoke-input");
    s->output = option(args, "--smoke-output");
    s->report = option(args, "--smoke-report");
    s->result = {{"version", QCoreApplication::applicationVersion()}, {"input", s->input},
                 {"output", s->output}, {"qmlLoaded", !engine.rootObjects().isEmpty()}};
    auto finish = [s](const QString &error) {
        if (s->finished) return;
        s->finished = true;
        s->result.insert("ok", error.isEmpty());
        s->result.insert("error", error);
        s->result.insert("inputProbed", s->loaded);
        s->result.insert("previewFrameDecoded", s->preview);
        s->result.insert("exportStarted", s->exporting);
        const QByteArray json = QJsonDocument(s->result).toJson();
        QSaveFile report(s->report);
        const bool saved = s->report != s->input && s->report != s->output
                           && report.open(QIODevice::WriteOnly) && report.write(json) == json.size()
                           && report.commit();
        if (!saved) qCritical("Cannot write smoke report: %s", qPrintable(s->report));
        qInfo().noquote() << json;
        QCoreApplication::exit(error.isEmpty() && saved ? 0 : 1);
    };
    auto beginExport = [s, &backend, &engine, finish] {
        if (!s->loaded || !s->preview || s->exporting || s->finished) return;
        s->exporting = true;
        qInfo("Smoke: trimming, splitting, moving and exporting");
        // The editor pauses before changing clip edges. Do the same here;
        // seeking a running GStreamer pipeline during a structural edit can
        // otherwise race its old stream position.
        if (auto *player = engine.rootObjects().first()->findChild<QMediaPlayer *>("player")) {
            player->pause();
            QMetaObject::invokeMethod(player, "finishPriming");
            player->setProperty("pendingPlay", false);
        }
        auto *timeline = backend.timeline();
        const double duration = timeline->duration();
        if (duration < 0.8) { finish("Input must be at least 0.8 seconds long"); return; }
        timeline->trimTo(0.2, true);
        timeline->trimTo(timeline->duration() - 0.2, false);
        timeline->split(timeline->duration() / 2);
        timeline->moveClip(1, 0);
        s->expectedDuration = duration - 0.4;
        s->result.insert("editedClips", timeline->clips().size());
        s->result.insert("expectedDuration", s->expectedDuration);
        if (timeline->clips().size() != 2) { finish("Trim/split/move failed"); return; }
        backend.exportClips(QUrl::fromLocalFile(s->output), timeline->clips());
    };
    QObject::connect(&backend, &Backend::loadError, &engine, [finish](const QString &e) { finish(e); });
    QObject::connect(&backend, &Backend::exportFailed, &engine, [finish](const QString &e) { finish(e); });
    QObject::connect(&backend, &Backend::infoChanged, &engine, [s, &backend, &engine, beginExport] {
        if (s->loaded || backend.timeline()->duration() <= 0) return;
        s->loaded = true;
        qInfo("Smoke: input probe completed");
        s->result.insert("inputProbed", true);
        // Exercise normal playback as well as the first-frame priming path.
        QTimer::singleShot(100, &engine, [s, &engine] {
            if (!s->preview && !s->exporting && !s->finished)
                QMetaObject::invokeMethod(engine.rootObjects().first(), "togglePlay");
        });
        beginExport();
    });
    QObject::connect(&backend, &Backend::exportDone, &engine, [s, finish](const QString &path) {
        const auto info = ffmpeg::probe(path);
        const auto frame = ffmpeg::thumbnail(path, 0.2);
        s->result.insert("outputDuration", info.duration);
        s->result.insert("outputWidth", info.width);
        s->result.insert("outputHeight", info.height);
        s->result.insert("outputAudio", info.audio);
        s->result.insert("outputFrameDecoded", !frame.isNull());
        const auto input = ffmpeg::probe(s->input);
        finish(info.ok && info.audio == input.audio && !frame.isNull()
                   && std::abs(info.duration - s->expectedDuration) < 0.15
               ? QString() : QStringLiteral("Export verification failed: ") + info.error);
    });
    auto *player = engine.rootObjects().isEmpty() ? nullptr
        : engine.rootObjects().first()->findChild<QMediaPlayer *>("player");
    if (player && player->videoSink()) {
        QTimer::singleShot(5000, &engine, [player] {
            qInfo() << "Smoke: player state" << player->source() << player->mediaStatus()
                    << player->playbackState() << player->position() << player->errorString();
        });
        QObject::connect(player->videoSink(), &QVideoSink::videoFrameChanged, &engine,
                         [s, beginExport](const QVideoFrame &frame) {
            if (!frame.isValid() || s->preview) return;
            s->preview = true;
            qInfo("Smoke: preview frame decoded");
            s->result.insert("previewFrameDecoded", true);
            QTimer::singleShot(0, QCoreApplication::instance(), beginExport);
        });
        QObject::connect(player, &QMediaPlayer::errorOccurred, &engine,
                         [finish](QMediaPlayer::Error, const QString &error) { finish(error); });
    }
    QTimer::singleShot(120000, &engine, [s, player, finish] {
        if (player) {
            s->result.insert("playerSource", player->source().toString());
            s->result.insert("mediaStatus", int(player->mediaStatus()));
            s->result.insert("playbackState", int(player->playbackState()));
            s->result.insert("playerPosition", double(player->position()));
            s->result.insert("playerError", player->errorString());
        }
        finish("Smoke test timed out (probe/preview/export)");
    });
    QTimer::singleShot(0, &engine, [s, &backend, player, finish] {
        if (s->report.isEmpty() || s->input.isEmpty() || s->output.isEmpty()
            || s->input == s->output || s->report == s->input || s->report == s->output
            || !player || !player->videoSink()) {
            finish("Require --smoke-input, distinct --smoke-output, --smoke-report and a QML video sink");
            return;
        }
        if (!backend.load(QUrl::fromLocalFile(s->input))) finish("Input load refused");
    });
}
