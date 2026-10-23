#pragma once

#include <QKeyEvent>
#include <QQuickWindow>
#include <QVariant>

// Match the character produced by the active keyboard layout. Native key
// codes can refer to a different character (notably punctuation on macOS).
class ClipMoveKeys : public QObject {
public:
    explicit ClipMoveKeys(QQuickWindow *window) : QObject(window), m_window(window) {
        window->installEventFilter(this);
    }

protected:
    bool eventFilter(QObject *, QEvent *event) override {
        if ((event->type() != QEvent::ShortcutOverride && event->type() != QEvent::KeyPress)
            || !m_window->property("editing").toBool())
            return false;
        const auto *key = static_cast<QKeyEvent *>(event);
        const bool bracketStart = key->text() == QStringLiteral("[")
            || (key->text().isEmpty() && key->key() == Qt::Key_BracketLeft);
        const bool bracketEnd = key->text() == QStringLiteral("]")
            || (key->text().isEmpty() && key->key() == Qt::Key_BracketRight);
        const bool bracket = bracketStart || bracketEnd;
        const bool dash = key->text() == QStringLiteral("\u2013")
            || key->text() == QStringLiteral("\u2014");
        // Option/Alt is how macOS types these characters; keep other Alt
        // shortcuts and all Control/Command combinations untouched.
        if ((key->modifiers() & (Qt::ControlModifier | Qt::MetaModifier))
            || ((key->modifiers() & Qt::AltModifier) && !dash && !bracket))
            return false;
        int direction = 0;
        if (key->text() == QStringLiteral("+"))
            direction = 1;
        else if (dash || key->text() == QStringLiteral("-") || key->text() == QStringLiteral("\u2212"))
            direction = -1;
        else if (key->text().isEmpty()) {
            if (key->key() == Qt::Key_Plus)
                direction = 1;
            else if (key->key() == Qt::Key_Minus)
                direction = -1;
        }
        if (!direction && !bracket)
            return false;
        event->accept();
        if (event->type() == QEvent::ShortcutOverride)
            return true;
        if (bracket) {
            if (key->isAutoRepeat())
                return true;
            return QMetaObject::invokeMethod(m_window, "trimClipAtPlayhead",
                                             Q_ARG(QVariant, QVariant(bracketStart)));
        }
        return QMetaObject::invokeMethod(m_window, "moveClipBy",
                                         Q_ARG(QVariant, QVariant(direction)));
    }

private:
    QQuickWindow *m_window;
};
