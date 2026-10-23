#pragma once

#include "filepicker.h"
#include <memory>

class MacFilePicker : public FilePicker {
public:
    explicit MacFilePicker(QObject *parent = nullptr);
    ~MacFilePicker() override;
    void openVideo() override;
    void exportVideo(const QUrl &suggestedUrl, const QList<int> &scaleHeights) override;
private:
    struct Private;
    std::unique_ptr<Private> d;
};
