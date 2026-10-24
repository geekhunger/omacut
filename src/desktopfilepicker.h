#pragma once

#include "filepicker.h"
#include <QPointer>

class QFileDialog;

// Self-contained desktop dialogs for Windows and Linux without a portal service.
class DesktopFilePicker : public FilePicker {
    Q_OBJECT
public:
    explicit DesktopFilePicker(QObject *parent = nullptr);
    ~DesktopFilePicker() override;
    void openVideo() override;
    void exportVideo(const QUrl &suggestedUrl, const QList<int> &scaleHeights) override;
private:
    bool raiseExisting();
    void show(QFileDialog *dialog);
    QPointer<QFileDialog> m_dialog;
};
