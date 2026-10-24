#include "desktopfilepicker.h"
#include <QComboBox>
#include <QFileDialog>
#include <QFileInfo>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QLabel>

DesktopFilePicker::DesktopFilePicker(QObject *parent) : FilePicker(parent) {}
DesktopFilePicker::~DesktopFilePicker() { if (m_dialog) delete m_dialog; }

bool DesktopFilePicker::raiseExisting() {
    if (!m_dialog) return false;
    m_dialog->raise();
    m_dialog->activateWindow();
    return true;
}

void DesktopFilePicker::show(QFileDialog *dialog) {
    m_dialog = dialog;
    dialog->setAttribute(Qt::WA_DeleteOnClose);
    dialog->setWindowModality(Qt::ApplicationModal);
    connect(dialog, &QDialog::finished, this, [this, dialog] {
        if (m_dialog == dialog) m_dialog = nullptr;
    });
    dialog->open();
}

void DesktopFilePicker::openVideo() {
    if (raiseExisting()) return;
    auto *dialog = new QFileDialog;
    dialog->setOption(QFileDialog::DontUseNativeDialog);
    dialog->setWindowTitle(QStringLiteral("Open Video File"));
    dialog->setFileMode(QFileDialog::ExistingFile);
    dialog->setNameFilters({QStringLiteral("Videos (*.mp4 *.mov *.m4v *.mkv *.webm *.avi *.mpeg *.mpg)"),
                            QStringLiteral("All files (*)")});
    connect(dialog, &QFileDialog::fileSelected, this, [this](const QString &path) {
        emit openSelected(QUrl::fromLocalFile(path));
    });
    show(dialog);
}

void DesktopFilePicker::exportVideo(const QUrl &suggestedUrl, const QList<int> &scaleHeights) {
    if (raiseExisting()) return;
    auto *dialog = new QFileDialog;
    dialog->setOption(QFileDialog::DontUseNativeDialog);
    dialog->setWindowTitle(QStringLiteral("Export Video"));
    dialog->setAcceptMode(QFileDialog::AcceptSave);
    dialog->setFileMode(QFileDialog::AnyFile);
    dialog->setNameFilter(QStringLiteral("MP4 video (*.mp4)"));
    dialog->setDefaultSuffix(QStringLiteral("mp4"));
    const QFileInfo suggested(suggestedUrl.toLocalFile());
    dialog->setDirectory(suggested.absolutePath());
    dialog->selectFile(suggested.fileName());
    auto *quality = new QComboBox(dialog);
    quality->addItem(QStringLiteral("Original"), 0);
    for (int height : scaleHeights)
        quality->addItem(QStringLiteral("%1p").arg(height), height);
    if (!scaleHeights.isEmpty()) {
        auto *row = new QWidget(dialog);
        auto *layout = new QHBoxLayout(row);
        layout->addWidget(new QLabel(QStringLiteral("Quality:"), row));
        layout->addWidget(quality);
        layout->addStretch();
        if (auto *grid = qobject_cast<QGridLayout *>(dialog->layout()))
            grid->addWidget(row, grid->rowCount(), 0, 1, grid->columnCount());
    }
    connect(dialog, &QFileDialog::fileSelected, this, [this, quality](const QString &path) {
        emit exportSelected(QUrl::fromLocalFile(path), quality->currentData().toInt());
    });
    show(dialog);
}
