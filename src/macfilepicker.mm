#include "macfilepicker.h"
#include <QPointer>
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

struct MacFilePicker::Private {
    NSSavePanel *panel = nil;
};

MacFilePicker::MacFilePicker(QObject *parent) : FilePicker(parent), d(new Private) {}
MacFilePicker::~MacFilePicker() {
    [d->panel cancel:nil];
}

void MacFilePicker::openVideo() {
    if (d->panel) {
        [d->panel orderFrontRegardless];
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    d->panel = panel;
    panel.title = @"Open Video File";
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *extension in @[@"mp4", @"mov", @"m4v", @"mkv", @"webm", @"avi", @"mpeg", @"mpg"])
        [types addObject:[UTType typeWithFilenameExtension:extension]];
    panel.allowedContentTypes = types;
    panel.allowsOtherFileTypes = YES;
    QPointer<MacFilePicker> self(this);
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (!self) return;
        self->d->panel = nil;
        if (response == NSModalResponseOK && panel.URL)
            emit self->openSelected(QUrl::fromLocalFile(QString::fromUtf8(panel.URL.path.UTF8String)));
    }];
}

void MacFilePicker::exportVideo(const QUrl &suggestedUrl, const QList<int> &scaleHeights) {
    if (d->panel) {
        [d->panel orderFrontRegardless];
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    d->panel = panel;
    panel.title = @"Export Video";
    panel.allowedContentTypes = @[UTTypeMPEG4Movie];
    panel.canCreateDirectories = YES;
    NSURL *suggested = [NSURL fileURLWithPath:[NSString stringWithUTF8String:suggestedUrl.toLocalFile().toUtf8().constData()]];
    panel.directoryURL = [suggested URLByDeletingLastPathComponent];
    panel.nameFieldStringValue = suggested.lastPathComponent;
    NSPopUpButton *quality = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(75, 8, 160, 28) pullsDown:NO];
    [quality addItemWithTitle:@"Original"];
    for (int height : scaleHeights)
        [quality addItemWithTitle:[NSString stringWithFormat:@"%dp", height]];
    if (!scaleHeights.isEmpty()) {
        NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 44)];
        NSTextField *label = [NSTextField labelWithString:@"Quality:"];
        label.frame = NSMakeRect(0, 12, 70, 22);
        [accessory addSubview:label];
        [accessory addSubview:quality];
        panel.accessoryView = accessory;
    }
    QPointer<MacFilePicker> self(this);
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (!self) return;
        self->d->panel = nil;
        if (response == NSModalResponseOK && panel.URL) {
            const int index = int(quality.indexOfSelectedItem);
            const int height = index > 0 ? scaleHeights.value(index - 1) : 0;
            emit self->exportSelected(QUrl::fromLocalFile(QString::fromUtf8(panel.URL.path.UTF8String)), height);
        }
    }];
}
