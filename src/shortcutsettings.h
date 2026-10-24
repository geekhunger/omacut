#pragma once

#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QKeySequence>
#include <QSettings>
#include <QStringList>
#include <QVariantMap>
#include <memory>

class ShortcutSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap overrides READ overrides NOTIFY overridesChanged)
public:
    explicit ShortcutSettings(const QString &file = {}, QObject *parent = nullptr) : QObject(parent) {
        if (file.isEmpty())
            m_settings = std::make_unique<QSettings>(QStringLiteral("com.omacom"), QStringLiteral("omacut"));
        else
            m_settings = std::make_unique<QSettings>(file, QSettings::IniFormat);
        m_overrides = QJsonDocument::fromJson(m_settings->value(QStringLiteral("keyboard/overrides"))
                                                .toByteArray()).object().toVariantMap();
    }
    QVariantMap overrides() const { return m_overrides; }
    Q_INVOKABLE QString normalizeSequence(const QString &sequence) const {
        return QKeySequence::fromString(sequence, QKeySequence::PortableText).toString(QKeySequence::PortableText);
    }
    Q_INVOKABLE void setBindings(const QString &action, const QStringList &sequences) {
        if (action.isEmpty()) return;
        m_overrides.insert(action, sequences);
        save();
    }
    Q_INVOKABLE void reset() {
        m_overrides.clear();
        save();
    }
signals:
    void overridesChanged();
private:
    void save() {
        m_settings->setValue(QStringLiteral("keyboard/overrides"),
                            QJsonDocument(QJsonObject::fromVariantMap(m_overrides)).toJson(QJsonDocument::Compact));
        m_settings->sync();
        emit overridesChanged();
    }
    std::unique_ptr<QSettings> m_settings;
    QVariantMap m_overrides;
};
