#pragma once

#include <QKeyEvent>
#include <QKeySequence>
#include <QMouseEvent>
#include <QQuickWindow>
#include <QVariant>

// One dispatcher handles both ordinary shortcuts and characters produced by
// non-US layouts, and captures replacements before any action can execute.
class ClipMoveKeys : public QObject {
public:
    explicit ClipMoveKeys(QQuickWindow *window) : QObject(window), m_window(window) {
        window->installEventFilter(this);
    }
protected:
    bool eventFilter(QObject *, QEvent *event) override {
        const QString recording = m_window->property("recordingShortcut").toString();
        if (!recording.isEmpty() && (event->type() == QEvent::MouseButtonRelease
                || event->type() == QEvent::NonClientAreaMouseButtonPress)) {
            const auto *mouse = static_cast<QMouseEvent *>(event);
            QMetaObject::invokeMethod(m_window, "cancelShortcutOutside",
                Q_ARG(QVariant, QVariant(mouse->position().x())),
                Q_ARG(QVariant, QVariant(mouse->position().y())));
        }
        if (!recording.isEmpty() && event->type() == QEvent::WindowDeactivate)
            QMetaObject::invokeMethod(m_window, "cancelShortcutCapture");
        if (event->type() != QEvent::ShortcutOverride && event->type() != QEvent::KeyPress)
            return false;
        const auto *key = static_cast<QKeyEvent *>(event);
        if (isModifier(key->key())) {
            if (!recording.isEmpty()) { event->accept(); return true; }
            return false;
        }
        const QString sequence = keySequence(key);
        if (sequence.isEmpty()) return false;
        if (!recording.isEmpty()) {
            event->accept();
            if (event->type() == QEvent::KeyPress && !key->isAutoRepeat())
                QMetaObject::invokeMethod(m_window, "assignShortcut",
                    Q_ARG(QVariant, QVariant(recording)), Q_ARG(QVariant, QVariant(sequence)));
            return true;
        }
        QVariant handled;
        QMetaObject::invokeMethod(m_window, "handleShortcut", Q_RETURN_ARG(QVariant, handled),
            Q_ARG(QVariant, QVariant(sequence)), Q_ARG(QVariant, QVariant(key->isAutoRepeat())),
            Q_ARG(QVariant, QVariant(event->type() == QEvent::ShortcutOverride)));
        if (handled.toBool()) { event->accept(); return true; }
        return false;
    }
private:
    static bool isModifier(int key) {
        return key == Qt::Key_Shift || key == Qt::Key_Control || key == Qt::Key_Alt
            || key == Qt::Key_Meta || key == Qt::Key_AltGr;
    }
    static QString keySequence(const QKeyEvent *event) {
        auto modifiers = event->modifiers() & ~(Qt::KeypadModifier | Qt::GroupSwitchModifier);
        int key = event->key();
        if (key == Qt::Key_Backtab) { key = Qt::Key_Tab; modifiers |= Qt::ShiftModifier; }
        const QString text = event->text();
        // Typed punctuation includes Shift/Option already: +, ?, brackets,
        // en/em dashes, etc. Command/Control combinations retain modifiers.
        if (text.size() == 1 && text.at(0).isPrint() && !text.at(0).isLetterOrNumber() && !text.at(0).isSpace()
            && !(modifiers & (Qt::ControlModifier | Qt::MetaModifier))) {
            key = text.at(0).unicode();
            modifiers = Qt::NoModifier;
        }
        if (key == 0 || key == Qt::Key_unknown) return {};
        return QKeySequence(QKeyCombination(modifiers, static_cast<Qt::Key>(key)))
            .toString(QKeySequence::PortableText);
    }
    QQuickWindow *m_window;
};
