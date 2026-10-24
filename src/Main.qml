import QtQuick
import QtQml
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtMultimedia
import "Format.js" as Format

ApplicationWindow {
    id: win
    width: 960
    height: 680
    minimumWidth: 640
    minimumHeight: 460
    visible: true
    title: backend.source.toString() === "" ? "omacut" : "omacut — " + fileName(backend.source)
    readonly property bool hasVideo: backend.source.toString() !== ""
    readonly property color accent: backend.themeAccent
    readonly property color accentForeground: backend.themeAccentForeground
    readonly property bool audioOutputReady: audioOutput !== null
    property var audioOutput: null
    property string noticeText: ""
    property bool helpVisible: false
    property bool quitConfirmVisible: false
    property bool openConfirmVisible: false
    readonly property string statusText: noticeText !== "" ? noticeText : backend.status

    readonly property var timeline: backend.timeline
    // Quitting only warns about unexported edits. One clip spanning the whole
    // first video is never dirty — that's just the source.
    readonly property bool unexported: hasVideo && timeline.unexported
    // Editing shortcuts go quiet while a dialog or the help overlay is up,
    // a probe is about to replace the timeline, or a handle is dragged.
    readonly property bool editing: hasVideo && timeline.duration > 0 && !quitConfirmVisible && !openConfirmVisible && !helpVisible && !backend.probing && !editBar.interacting

    Material.theme: Material.Dark
    Material.accent: win.accent
    color: "#0e0e10"

    function fileName(url) {
        var s = url.toString();
        return s === "" ? "" : decodeURIComponent(s.substring(s.lastIndexOf('/') + 1));
    }
    function showNotice(text) {
        noticeText = text;
        noticeTimer.restart();
    }
    // Not while exporting: the export would mark the new edit as exported.
    // Replacing an unexported edit asks first, like quitting does.
    function openVideo() {
        if (backend.busy)
            return;
        if (unexported) {
            player.pause();
            openConfirmVisible = true;
            return;
        }
        backend.openVideoDialog();
    }
    function addVideo() {
        if (backend.busy)
            return;
        player.pause();
        backend.addVideoDialog(editBar.playheadSec);
    }
    // Dropped videos open into an empty window, and otherwise join the edit
    // after the clip under the playhead, in the order dropped, the way the +
    // button adds one. Adding is undoable, so a stray drop costs nothing.
    // Probing happens in the background, in drop order; a file that won't
    // open is skipped and the rest go on. When some made it, one notice
    // counts the skipped, since each error replaces the last.
    function dropVideos(urls) {
        return backend.addVideos(urls, editBar.playheadSec);
    }
    function exportVideo() {
        if (!win.hasVideo || timeline.duration <= 0 || backend.busy)
            return;
        player.pause();
        backend.exportDialog();
    }
    function ensureAudioOutput() {
        if (audioOutput === null && win.hasVideo)
            audioOutput = audioOutputComponent.createObject(win);
    }
    function releaseAudioOutput() {
        if (audioOutput === null)
            return;
        var oldAudioOutput = audioOutput;
        audioOutput = null;
        oldAudioOutput.destroy();
    }
    function playing() {
        return player.playbackState === MediaPlayer.PlayingState && !player.priming;
    }
    function togglePlay() {
        if (!win.hasVideo || timeline.duration <= 0)
            return;
        edgeClip = -1;
        ensureAudioOutput();
        if (playing()) {
            player.pause();
            return;
        }
        // From the playhead, or from the top once at the end.
        var t = editBar.playheadSec >= timeline.duration - 0.03 ? 0 : editBar.playheadSec;
        var i = timeline.clipAt(t), clip = timeline.clips[i];
        editBar.playheadSec = t;
        player.show(i, clip.in + t - clip.start, true);
    }
    function seekTo(seconds) {
        if (!win.hasVideo || timeline.duration <= 0)
            return;
        edgeClip = -1;
        var t = Math.max(0, Math.min(seconds, timeline.duration));
        var i = timeline.clipAt(t), clip = timeline.clips[i];
        editBar.playheadSec = t;
        player.show(i, clip.in + t - clip.start, playing());
    }
    // A shared boundary is both one clip's out and the next clip's in.
    // Retain the clip we showed so reversing direction stays on that clip.
    property int edgeClip: -1
    property int edgeDirection: 0
    function jumpToClipEdge(direction) {
        if (!win.hasVideo || timeline.duration <= 0)
            return;
        var i = edgeClip >= 0 ? edgeClip : timeline.clipAt(editBar.playheadSec);
        if (edgeClip >= 0 && edgeDirection === direction)
            i = Math.max(0, Math.min(i + direction, timeline.clips.length - 1));
        player.pause();
        player.finishPriming();
        edgeClip = i;
        edgeDirection = direction;
        var clip = timeline.clips[i];
        editBar.playheadSec = direction > 0 ? clip.end : clip.start;
        // The out point is exclusive: preview this clip's last frame rather
        // than the following clip's first frame, as when dragging its handle.
        var sourceTime = direction > 0 ? Math.max(clip.in, clip.out - 0.001) : clip.in;
        player.show(i, sourceTime, false);
    }
    // Moves the clip under the playhead one place earlier or later, keeping
    // the playhead on the same frame of it.
    function moveClipBy(direction) {
        var atEdge = edgeClip >= 0;
        var oldEdgeDirection = edgeDirection;
        var t = editBar.playheadSec, i = atEdge ? edgeClip : timeline.clipAt(t);
        var into = t - timeline.clipStart(i);
        var target = i + direction;
        if (i < 0 || target < 0 || target >= timeline.clips.length)
            return;
        timeline.moveClip(i, target);
        if (atEdge) {
            // An out point belongs to the previewed clip even though clipAt
            // assigns its time to the following clip. Keep that association
            // through the move, including for the next +/- or Tab press.
            edgeClip = target;
            edgeDirection = oldEdgeDirection;
            var clip = timeline.clips[target];
            editBar.playheadSec = clip.start + into;
            var sourceTime = oldEdgeDirection > 0 ? Math.max(clip.in, clip.out - 0.001) : clip.in;
            player.show(target, sourceTime, false);
        } else {
            seekTo(timeline.clipStart(target) + into);
        }
    }
    property bool quitting: false
    function trimClipAtPlayhead(start) {
        var index = edgeClip >= 0 ? edgeClip : timeline.clipAt(editBar.playheadSec);
        if (index < 0 || index >= timeline.clips.length) return;
        var clip = timeline.clips[index];
        var at = clip.in + editBar.playheadSec - clip.start;
        timeline.setClip(index, start ? at : clip.in, start ? clip.out : at);
        clip = timeline.clips[index];
        // An invalid trim (e.g. a zero-length result) leaves everything alone.
        if (Math.abs((start ? clip.in : clip.out) - at) > 0.000001) return;
        player.pause();
        player.finishPriming();
        edgeClip = index;
        edgeDirection = start ? -1 : 1;
        editBar.playheadSec = start ? clip.start : clip.end;
        player.show(index, start ? clip.in : Math.max(clip.in, clip.out - 0.001), false);
    }
    function requestQuit() {
        if (unexported) {
            if (player.playbackState === MediaPlayer.PlayingState)
                player.pause();
            quitConfirmVisible = true;
            return;
        }
        forceQuit();
    }
    // Closing the window is what reliably ends the app (quitOnLastWindowClosed);
    // Qt.quit() alone has proven ignorable in a live session, so it's only the
    // backstop. The quitting flag stops onClosing from re-asking on the way out.
    function forceQuit() {
        quitting = true;
        player.stop();
        releaseAudioOutput();
        win.close();
        Qt.quit();
    }

    Component.onCompleted: ensureAudioOutput()
    onHasVideoChanged: {
        if (hasVideo) {
            ensureAudioOutput();
        } else {
            player.stop();
            releaseAudioOutput();
        }
    }
    onClosing: (close) => {
        if (win.quitting)
            return;
        // A close with the open confirmation up just puts it away, rather
        // than stacking the quit confirmation on top of it.
        if (win.openConfirmVisible) {
            close.accepted = false;
            win.openConfirmVisible = false;
            return;
        }
        if (win.unexported) {
            close.accepted = false;
            if (player.playbackState === MediaPlayer.PlayingState)
                player.pause();
            win.quitConfirmVisible = true;
            return;
        }
        forceQuit();
    }

    property var shortcutOverrides: shortcutStore.overrides
    property string recordingShortcut: ""
    property int recordingShortcutIndex: -1
    property Item shortcutCaptureItem: null
    property string shortcutMessage: ""
    readonly property var shortcutDefinitions: [
        {
                "id": "play",
                "label": "Play / pause",
                "keys": [
                        "Space"
                ],
                "scope": "edit"
        },
        {
                "id": "jump10",
                "label": "Jump to 10% of the edit",
                "keys": [
                        "1"
                ],
                "scope": "edit"
        },
        {
                "id": "jump20",
                "label": "Jump to 20% of the edit",
                "keys": [
                        "2"
                ],
                "scope": "edit"
        },
        {
                "id": "jump30",
                "label": "Jump to 30% of the edit",
                "keys": [
                        "3"
                ],
                "scope": "edit"
        },
        {
                "id": "jump40",
                "label": "Jump to 40% of the edit",
                "keys": [
                        "4"
                ],
                "scope": "edit"
        },
        {
                "id": "jump50",
                "label": "Jump to 50% of the edit",
                "keys": [
                        "5"
                ],
                "scope": "edit"
        },
        {
                "id": "jump60",
                "label": "Jump to 60% of the edit",
                "keys": [
                        "6"
                ],
                "scope": "edit"
        },
        {
                "id": "jump70",
                "label": "Jump to 70% of the edit",
                "keys": [
                        "7"
                ],
                "scope": "edit"
        },
        {
                "id": "jump80",
                "label": "Jump to 80% of the edit",
                "keys": [
                        "8"
                ],
                "scope": "edit"
        },
        {
                "id": "jump90",
                "label": "Jump to 90% of the edit",
                "keys": [
                        "9"
                ],
                "scope": "edit"
        },
        {
                "id": "jumpStart",
                "label": "Jump to the start",
                "keys": [
                        "0"
                ],
                "scope": "edit"
        },
        {
                "id": "jumpEnd",
                "label": "Jump to the end",
                "keys": [],
                "scope": "edit"
        },
        {
                "id": "seekBack1",
                "label": "Move playhead back 1s",
                "keys": [
                        "Left"
                ],
                "scope": "edit"
        },
        {
                "id": "seekForward1",
                "label": "Move playhead forward 1s",
                "keys": [
                        "Right"
                ],
                "scope": "edit"
        },
        {
                "id": "seekBack5",
                "label": "Move playhead back 5s",
                "keys": [
                        "Shift+Left"
                ],
                "scope": "edit"
        },
        {
                "id": "seekForward5",
                "label": "Move playhead forward 5s",
                "keys": [
                        "Shift+Right"
                ],
                "scope": "edit"
        },
        {
                "id": "seekBackFine",
                "label": "Move playhead back 0.2s",
                "keys": [
                        "Alt+Left"
                ],
                "scope": "edit"
        },
        {
                "id": "seekForwardFine",
                "label": "Move playhead forward 0.2s",
                "keys": [
                        "Alt+Right"
                ],
                "scope": "edit"
        },
        {
                "id": "previousEdge",
                "label": "Clip in; repeat for previous clip",
                "keys": [
                        "Shift+Tab"
                ],
                "scope": "edit"
        },
        {
                "id": "nextEdge",
                "label": "Clip out; repeat for next clip",
                "keys": [
                        "Tab"
                ],
                "scope": "edit"
        },
        {
                "id": "split",
                "label": "Split the clip at the playhead",
                "keys": [
                        "S"
                ],
                "scope": "edit"
        },
        {
                "id": "remove",
                "label": "Remove the clip",
                "keys": [
                        "X",
                        "Delete",
                        "Backspace"
                ],
                "scope": "edit"
        },
        {
                "id": "earlier",
                "label": "Move the clip earlier",
                "keys": [
                        "-",
                        "−",
                        "–",
                        "—"
                ],
                "scope": "edit"
        },
        {
                "id": "later",
                "label": "Move the clip later",
                "keys": [
                        "+"
                ],
                "scope": "edit"
        },
        {
                "id": "trimIn",
                "label": "Clip start (in) to playhead",
                "keys": [
                        "["
                ],
                "scope": "edit"
        },
        {
                "id": "trimOut",
                "label": "Clip end (out) to playhead",
                "keys": [
                        "]"
                ],
                "scope": "edit"
        },
        {
                "id": "undo",
                "label": "Undo",
                "keys": [
                        "Ctrl+Z"
                ],
                "scope": "edit"
        },
        {
                "id": "redo",
                "label": "Redo",
                "keys": [
                        "Ctrl+Shift+Z"
                ],
                "scope": "edit"
        },
        {
                "id": "zoom",
                "label": "Zoom in / show the whole edit",
                "keys": [
                        "Z"
                ],
                "scope": "edit"
        },
        {
                "id": "frame",
                "label": "Save the playhead frame as a PNG",
                "keys": [
                        "F"
                ],
                "scope": "edit"
        },
        {
                "id": "open",
                "label": "Open a video",
                "keys": [
                        "Ctrl+O"
                ],
                "scope": "edit"
        },
        {
                "id": "add",
                "label": "Add a video after this clip",
                "keys": [
                        "Ctrl+Shift+O"
                ],
                "scope": "edit"
        },
        {
                "id": "export",
                "label": "Export",
                "keys": [
                        "Ctrl+S"
                ],
                "scope": "edit"
        },
        {
                "id": "quit",
                "label": "Quit",
                "keys": [
                        "Q"
                ],
                "scope": "edit"
        },
        {
                "id": "help",
                "label": "Show / hide these shortcuts",
                "keys": [
                        "?"
                ],
                "scope": "global"
        },
        {
                "id": "closeHelp",
                "label": "Close this help",
                "keys": [
                        "X"
                ],
                "scope": "help"
        },
        {
                "id": "dismiss",
                "label": "Dismiss the current dialog",
                "keys": [
                        "Escape"
                ],
                "scope": "global"
        }
]
    onHelpVisibleChanged: {
        if (!helpVisible) cancelShortcutCapture();
    }
    function shortcutSequences(action) {
        if (Object.prototype.hasOwnProperty.call(shortcutOverrides, action)) {
            var stored = shortcutOverrides[action];
            return Array.from(typeof stored === "string" ? [stored] : stored).map(k => shortcutStore.normalizeSequence(k));
        }
        for (var i = 0; i < shortcutDefinitions.length; ++i)
            if (shortcutDefinitions[i].id === action)
                return shortcutDefinitions[i].keys.map(k => shortcutStore.normalizeSequence(k));
        return [];
    }
    function shortcutDisplay(sequence) {
        var platformSequence = Qt.platform.os === "osx"
            ? sequence.replace(/Ctrl\+/g, "Cmd+").replace(/Meta\+/g, "Ctrl+")
            : sequence;
        return platformSequence
            .replace(/Left/g, "←").replace(/Right/g, "→")
            .replace(/^Del$/, "Delete").replace(/^Esc$/, "Escape");
    }
    function beginShortcutCapture(action, index, field) {
        recordingShortcutIndex = index;
        shortcutCaptureItem = field || null;
        recordingShortcut = action;
        shortcutMessage = "Press the new key or key combination.";
    }
    function cancelShortcutCapture() {
        recordingShortcut = "";
        shortcutCaptureItem = null;
        shortcutMessage = "";
    }
    function cancelShortcutOutside(x, y) {
        if (shortcutCaptureItem) {
            var point = shortcutCaptureItem.mapFromItem(win.contentItem, x, y);
            if (point.x >= 0 && point.y >= 0 && point.x <= shortcutCaptureItem.width
                    && point.y <= shortcutCaptureItem.height) return;
        }
        cancelShortcutCapture();
    }
    function ensureShortcutVisible(item) {
        var y = item.mapToItem(helpColumn, 0, 0).y;
        if (y < shortcutList.contentY) shortcutList.contentY = y;
        else if (y + item.height > shortcutList.contentY + shortcutList.height)
            shortcutList.contentY = Math.min(shortcutList.contentHeight - shortcutList.height,
                                              y + item.height - shortcutList.height);
    }
    function assignShortcut(action, sequence) {
        var definition = shortcutDefinitions.filter(d => d.id === action)[0];
        for (var i = 0; i < shortcutDefinitions.length; ++i) {
            var other = shortcutDefinitions[i];
            if (other.id === action) continue;
            // Editing and help-only actions can intentionally share X.
            if ((definition.scope === "help" && other.scope === "edit")
                    || (definition.scope === "edit" && other.scope === "help")) continue;
            if (shortcutSequences(other.id).indexOf(sequence) >= 0) {
                shortcutMessage = "Already assigned to “" + other.label + "”. Choose another shortcut.";
                return false;
            }
        }
        var keys = Array.from(shortcutSequences(action));
        if (keys.indexOf(sequence) >= 0 && keys.indexOf(sequence) !== recordingShortcutIndex) {
            shortcutMessage = "This action already has that shortcut. Choose another one.";
            return false;
        }
        if (recordingShortcutIndex < 0) keys.push(sequence);
        else keys[recordingShortcutIndex] = sequence;
        shortcutStore.setBindings(action, keys);
        recordingShortcut = "";
        shortcutCaptureItem = null;
        shortcutMessage = "Shortcut saved.";
        return true;
    }
    function removeShortcut(action, index) {
        var keys = Array.from(shortcutSequences(action));
        if (index < 0 || index >= keys.length) return;
        keys.splice(index, 1);
        if (recordingShortcut === action) recordingShortcut = "";
        shortcutStore.setBindings(action, keys);
        shortcutMessage = "Shortcut removed.";
    }
    function shortcutEnabled(action) {
        if (action === "closeHelp") return helpVisible;
        if (action === "help") return !quitConfirmVisible && !openConfirmVisible;
        if (action === "dismiss") return quitConfirmVisible || openConfirmVisible || helpVisible;
        if (helpVisible) return false;
        if (action === "export") return hasVideo && timeline.duration > 0 && !backend.busy && !openConfirmVisible;
        if (action === "open") return !quitConfirmVisible && !openConfirmVisible && !backend.busy;
        if (action === "play") return hasVideo && !quitConfirmVisible && !openConfirmVisible;
        if (action === "quit") return !quitConfirmVisible && !openConfirmVisible;
        if (!editing) return false;
        if (action === "undo") return timeline.canUndo;
        if (action === "redo") return timeline.canRedo;
        if (action === "frame" || action === "add") return !backend.busy;
        return true;
    }
    function handleShortcut(sequence, repeated, preview) {
        for (var i = 0; i < shortcutDefinitions.length; ++i) {
            var action = shortcutDefinitions[i].id;
            if (!shortcutEnabled(action) || shortcutSequences(action).indexOf(sequence) < 0) continue;
            if (preview) return true;
            var mayRepeat = action.indexOf("seek") === 0 || action === "earlier" || action === "later"
                || action === "undo" || action === "redo";
            if (!repeated || mayRepeat) triggerShortcut(action);
            return true;
        }
        return false;
    }
    function triggerShortcut(action) {
        if (action.indexOf("jump") === 0 && action !== "jumpStart" && action !== "jumpEnd") {
            seekTo(timeline.duration * parseInt(action.substring(4)) / 100); return;
        }
        switch (action) {
        case "jumpStart": seekTo(0); break;
        case "jumpEnd": seekTo(timeline.duration); break;
        case "play": togglePlay(); break;
        case "seekBack1": seekTo(editBar.playheadSec - 1); break;
        case "seekForward1": seekTo(editBar.playheadSec + 1); break;
        case "seekBack5": seekTo(editBar.playheadSec - 5); break;
        case "seekForward5": seekTo(editBar.playheadSec + 5); break;
        case "seekBackFine": seekTo(editBar.playheadSec - 0.2); break;
        case "seekForwardFine": seekTo(editBar.playheadSec + 0.2); break;
        case "previousEdge": jumpToClipEdge(-1); break;
        case "nextEdge": jumpToClipEdge(1); break;
        case "split": timeline.split(editBar.playheadSec); break;
        case "remove": timeline.removeAt(editBar.playheadSec); break;
        case "earlier": moveClipBy(-1); break;
        case "later": moveClipBy(1); break;
        case "trimIn": trimClipAtPlayhead(true); break;
        case "trimOut": trimClipAtPlayhead(false); break;
        case "undo": timeline.undo(); break;
        case "redo": timeline.redo(); break;
        case "zoom": editBar.toggleZoom(); break;
        case "frame": backend.saveFrame(editBar.playheadSec); break;
        case "open": openVideo(); break;
        case "add": addVideo(); break;
        case "export": quitConfirmVisible = false; exportVideo(); break;
        case "quit": requestQuit(); break;
        case "help": helpVisible = !helpVisible; break;
        case "closeHelp": helpVisible = false; break;
        case "dismiss":
            if (quitConfirmVisible) quitConfirmVisible = false;
            else if (openConfirmVisible) openConfirmVisible = false;
            else if (helpVisible) helpVisible = false;
            break;
        }
    }

    MediaPlayer {
        id: player
        objectName: "player"
        videoOutput: videoOut
        audioOutput: win.audioOutput

        // The clip on screen, and where to go once a newly set source has
        // loaded (pendingMs is -1 when nothing is waiting).
        property int clip: -1
        property int pendingMs: -1
        property bool pendingPlay: false
        // Switching sources first reports the old video as loaded again; only
        // a load that follows the new one starting counts.
        property bool loadStarted: false
        // A freshly loaded source shows black until played; playing it muted
        // until the first frame arrives, then pausing, puts that frame up.
        property bool priming: false
        property int primeMs: 0

        // Shows sourceTime in clip index, and plays on from there if asked.
        function show(index, sourceTime, andPlay) {
            var url = backend.videos[timeline.clips[index].source].url;
            var ms = Math.round(sourceTime * 1000);
            clip = index;
            // Compared as text: url values are never identical as objects.
            if (source.toString() !== url.toString() || mediaStatus === MediaPlayer.LoadingMedia) {
                pendingMs = ms;
                pendingPlay = andPlay;
                loadStarted = mediaStatus === MediaPlayer.LoadingMedia && source.toString() === url.toString();
                source = url;
                return;
            }
            pendingMs = -1;
            finishPriming();
            position = ms;
            if (andPlay)
                play();
        }

        // Moves a load still in progress to sourceTime in clip index, keeping
        // whether it plays once loaded.
        function retarget(index, sourceTime) {
            var url = backend.videos[timeline.clips[index].source].url;
            if (source.toString() !== url.toString()) {
                show(index, sourceTime, pendingPlay);
                return;
            }
            clip = index;
            pendingMs = Math.round(sourceTime * 1000);
        }

        function startPriming(ms) {
            win.ensureAudioOutput();
            priming = true;
            primeMs = ms;
            position = ms;
            play();
            primeFallback.restart();
        }

        function finishPriming() {
            if (!priming)
                return;
            primeFallback.stop();
            pause();
            position = primeMs;
            priming = false;
        }

        onMediaStatusChanged: {
            // A video that won't load leaves nothing to wait for.
            if (mediaStatus === MediaPlayer.InvalidMedia)
                pendingMs = -1;
            if (mediaStatus === MediaPlayer.LoadingMedia)
                loadStarted = true;
            // Seeking or playing from inside this handler makes the player
            // load the video over again, so it waits for the handler to return.
            if (pendingMs >= 0 && loadStarted
                    && (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia))
                Qt.callLater(takePending);
        }
        function takePending() {
            if (pendingMs < 0)
                return;
            var ms = pendingMs;
            pendingMs = -1;
            if (pendingPlay) {
                position = ms;
                play();
            } else {
                startPriming(ms);
            }
        }
        onPositionChanged: {
            if (priming) {
                if (player.position > primeMs)
                    finishPriming();
                return;
            }
            if (pendingMs >= 0 || clip < 0 || clip >= timeline.clips.length)
                return;
            if (win.edgeClip >= 0)
                return;
            var c = timeline.clips[clip], t = player.position / 1000;
            // Play the clips in order: carry on into a clip that continues
            // this one, jump to any other, and stop after the last.
            if (playbackState === MediaPlayer.PlayingState && t >= c.out - 0.03) {
                if (clip + 1 >= timeline.clips.length) {
                    pause();
                    editBar.playheadSec = timeline.duration;
                    return;
                }
                var next = timeline.clips[clip + 1];
                if (next.source !== c.source || Math.abs(next.in - c.out) > 0.05) {
                    show(clip + 1, next.in, true);
                    return;
                }
                clip += 1;
                c = next;
            }
            if (!editBar.interacting)
                editBar.playheadSec = c.start + Math.max(0, Math.min(t, c.out) - c.in);
        }
    }

    // After an edit, the clip under the playhead may be another one now, or
    // gone, so put the playhead's frame back up.
    Connections {
        target: win.timeline
        function onChanged() {
            win.edgeClip = -1;
            Qt.callLater(win.resync);
        }
    }
    function resync() {
        if (!hasVideo || timeline.duration <= 0 || editBar.interacting || edgeClip >= 0)
            return;
        var t = Math.min(editBar.playheadSec, timeline.duration);
        var i = timeline.clipAt(t), clip = timeline.clips[i];
        var sourceTime = clip.in + t - clip.start;
        // Edited while a video loads: aim the wait at the playhead's clip now,
        // not the one it was started for.
        if (player.pendingMs >= 0) {
            player.retarget(i, sourceTime);
            return;
        }
        // Still playing the right stretch, e.g. after a split: no need to seek.
        if (playing() && backend.videos[clip.source].url.toString() === player.source.toString()
                && Math.abs(sourceTime - player.position / 1000) < 0.1) {
            player.clip = i;
            return;
        }
        editBar.playheadSec = t;
        player.show(i, sourceTime, playing());
    }

    Component {
        id: audioOutputComponent
        AudioOutput {
            // Follows the system's default output as it changes, between
            // headphones, speakers, monitor audio, etc. Created with the
            // output, so nothing watches devices before a video is open.
            property MediaDevices devices: MediaDevices {}
            device: devices.defaultAudioOutput
            muted: player.priming
        }
    }

    Timer {
        id: primeFallback
        interval: 250
        repeat: false
        onTriggered: player.finishPriming()
    }

    Timer {
        id: noticeTimer
        interval: 5000
        repeat: false
        onTriggered: win.noticeText = ""
    }

    component DialogButton: Rectangle {
        id: dialogButton
        width: dialogButtonLabel.implicitWidth + 28
        height: 34
        radius: 8

        property string text: ""
        property bool primary: false
        signal clicked()

        color: primary ? win.accent : "#2c2c2f"
        border.color: activeFocus ? (primary ? win.accentForeground : win.accent) : "transparent"
        border.width: activeFocus ? 2 : 0

        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Keys.onSpacePressed: clicked()

        Label {
            id: dialogButtonLabel
            anchors.centerIn: parent
            text: dialogButton.text
            color: dialogButton.primary ? win.accentForeground : "white"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dialogButton.clicked()
        }
    }

    component IconButton: Rectangle {
        id: iconButton
        implicitWidth: 44
        implicitHeight: 44
        radius: 22

        property string iconName: "play"
        property color iconColor: "white"
        property color buttonColor: "#2c2c2f"
        property string tipText: ""
        signal clicked()

        color: buttonColor
        opacity: enabled ? 1 : 0.45

        HoverHandler { id: iconHover }
        ToolTip.visible: iconHover.hovered && tipText !== ""
        ToolTip.text: tipText

        Canvas {
            id: iconCanvas
            anchors.centerIn: parent
            width: 24
            height: 24

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = iconButton.iconColor;
                ctx.strokeStyle = iconButton.iconColor;
                ctx.lineWidth = 2.4;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";

                if (iconButton.iconName === "pause") {
                    ctx.fillRect(7, 5, 4, 14);
                    ctx.fillRect(14, 5, 4, 14);
                } else if (iconButton.iconName === "play") {
                    ctx.beginPath();
                    ctx.moveTo(8, 5);
                    ctx.lineTo(8, 19);
                    ctx.lineTo(19, 12);
                    ctx.closePath();
                    ctx.fill();
                } else if (iconButton.iconName === "plus") {
                    ctx.beginPath();
                    ctx.moveTo(12, 5);
                    ctx.lineTo(12, 19);
                    ctx.moveTo(5, 12);
                    ctx.lineTo(19, 12);
                    ctx.stroke();
                } else if (iconButton.iconName === "close") {
                    ctx.beginPath();
                    ctx.moveTo(6, 6);
                    ctx.lineTo(18, 18);
                    ctx.moveTo(18, 6);
                    ctx.lineTo(6, 18);
                    ctx.stroke();
                } else if (iconButton.iconName === "download") {
                    ctx.beginPath();
                    ctx.moveTo(12, 4);
                    ctx.lineTo(12, 14);
                    ctx.stroke();

                    ctx.beginPath();
                    ctx.moveTo(7, 10);
                    ctx.lineTo(12, 15);
                    ctx.lineTo(17, 10);
                    ctx.stroke();

                    ctx.beginPath();
                    ctx.moveTo(6, 20);
                    ctx.lineTo(18, 20);
                    ctx.stroke();
                }
            }

            Connections {
                target: iconButton
                function onIconNameChanged() { iconCanvas.requestPaint(); }
                function onIconColorChanged() { iconCanvas.requestPaint(); }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: iconButton.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.clicked()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.hasVideo ? 16 : 0
        spacing: 14

        // --- video preview ---
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: win.hasVideo ? 12 : 0
            color: "black"
            clip: true

            VideoOutput {
                id: videoOut
                anchors.fill: parent
            }
            Connections {
                target: videoOut.videoSink
                function onVideoFrameChanged(frame) {
                    player.finishPriming();
                }
            }

            // Only the empty state opens on a preview click: with a video
            // loaded, a stray click must not reach the file picker at all.
            MouseArea {
                anchors.fill: parent
                enabled: !win.hasVideo
                cursorShape: Qt.PointingHandCursor
                onClicked: openVideo()
            }

            Button {
                id: openVideoButton
                anchors.centerIn: parent
                visible: !win.hasVideo
                text: "Open a video"
                highlighted: true
                focusPolicy: Qt.NoFocus
                font.pixelSize: 18
                Material.foreground: win.accentForeground
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }
                contentItem: Label {
                    text: openVideoButton.text
                    font: openVideoButton.font
                    color: win.accentForeground
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: openVideo()
            }

            // With no video open there's no status line, so a file that
            // won't open says why here.
            Label {
                anchors.top: openVideoButton.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, parent.width - 32)
                visible: !win.hasVideo && win.noticeText !== ""
                textFormat: Text.PlainText
                text: win.noticeText
                color: win.accent
                font.pixelSize: 13
                font.family: "monospace"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }

        // --- timeline ---
        RowLayout {
            visible: win.hasVideo
            Layout.fillWidth: true
            spacing: 10

            IconButton {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                iconName: player.playbackState === MediaPlayer.PlayingState && !player.priming ? "pause" : "play"
                tipText: player.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"
                enabled: timeline.duration > 0
                onClicked: togglePlay()
            }

            EditBar {
                id: editBar
                objectName: "editBar"
                Layout.fillWidth: true
                // Frozen while a probe is in flight: it is about to replace
                // or extend the timeline the bar is showing.
                enabled: !backend.probing
                accent: win.accent
                accentForeground: win.accentForeground
                edgeClip: win.edgeClip
                onScrub: (seconds) => {
                    player.pause();
                    seekTo(seconds);
                }
                onScrubClip: (index, sourceTime) => {
                    win.edgeClip = -1;
                    player.pause();
                    player.show(index, sourceTime, false);
                }
            }

            IconButton {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                iconName: "plus"
                tipText: "Add a video"
                enabled: timeline.duration > 0 && !backend.busy
                onClicked: addVideo()
            }

            IconButton {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                iconName: "download"
                tipText: "Export"
                enabled: timeline.duration > 0 && !backend.busy
                onClicked: exportVideo()
            }
        }

        // --- status line ---
        Item {
            visible: win.hasVideo
            Layout.fillWidth: true
            Layout.preferredHeight: 26

            Label {
                anchors.centerIn: parent
                width: parent.width
                visible: win.statusText !== ""
                // ffprobe's and ffmpeg's errors are shown as they are.
                textFormat: Text.PlainText
                text: win.statusText
                color: win.noticeText !== "" ? win.accent : "#b8b8bc"
                font.pixelSize: 13
                font.family: "monospace"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideMiddle
            }

            Label {
                anchors.centerIn: parent
                visible: win.statusText === "" && timeline.duration > 0 && !editBar.trimming
                textFormat: Text.StyledText
                text: Format.fmt(editBar.playheadSec) + " (" + Format.fmt(win.timeline.duration) + ")"
                    + (editBar.zoomed ? " · <font color=\"" + win.accent + "\">zoomed</font>" : "")
                color: "#d6d6da"
                font.pixelSize: 13
                font.family: "monospace"
            }
        }
    }

    DropArea {
        id: videoDropArea
        objectName: "videoDropArea"
        anchors.fill: parent
        z: 5
        enabled: !win.quitConfirmVisible && !win.openConfirmVisible && !win.helpVisible && !backend.busy
        // Only local files: "file:-report" or "file:http://..." would reach
        // ffprobe as an option or an address, and "file:////host/..." is a
        // network share.
        onEntered: (drag) => {
            drag.accepted = drag.hasUrls && drag.urls.length > 0
                && drag.urls.every((url) => /^file:\/\/\/(?!\/)/.test(url.toString()));
        }
        onDropped: (drop) => {
            player.pause();
            player.pendingPlay = false;
            if (win.dropVideos(drop.urls))
                drop.accept(Qt.CopyAction);
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 8
            visible: videoDropArea.containsDrag
            color: "#cc0e0e10"
            border.color: win.accent
            border.width: 2
            radius: 12
            Label {
                anchors.centerIn: parent
                text: win.hasVideo ? "Drop to add to the edit" : "Drop a video to open it"
                font.pixelSize: 20
                color: win.accent
            }
        }
    }

    // --- subtle help toggle in the corner ---
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
        width: 24
        height: 24
        radius: 12
        color: helpHover.hovered ? "#2c2c2f" : "transparent"

        Text {
            anchors.centerIn: parent
            text: "?"
            color: helpHover.hovered ? "white" : "#7a7a80"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        HoverHandler {
            id: helpHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: win.helpVisible = !win.helpVisible
        }
    }

    // --- editable hotkey overlay ---
    Rectangle {
        visible: win.helpVisible
        anchors.fill: parent
        color: "#cc000000"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Rectangle {
            objectName: "helpPanel"
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 700)
            height: helpLayout.height + 48
            radius: 12
            color: "#1c1c1e"
            Column {
                id: helpLayout
                width: parent.width - 48
                anchors.centerIn: parent
                spacing: 12
                Label {
                    text: "Keyboard shortcuts"
                    color: "white"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    height: 32
                    verticalAlignment: Text.AlignVCenter
                }
                Label {
                    objectName: "shortcutStatus"
                    width: parent.width
                    text: win.shortcutMessage || "Click a yellow shortcut to change it; + adds an alternative, − removes one."
                    color: win.recordingShortcut !== "" ? win.accent : "#b6b6bc"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Flickable {
                    id: shortcutList
                    objectName: "shortcutList"
                    width: parent.width
                    height: Math.min(contentHeight, Math.max(90, win.height - 230))
                    contentWidth: width
                    contentHeight: helpColumn.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    WheelHandler {
                        target: null
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(event) {
                            // Keep macOS natural scrolling and trackpad momentum;
                            // make the long list a little quicker to browse.
                            const delta = event.pixelDelta.y !== 0
                                ? event.pixelDelta.y : event.angleDelta.y / 120 * 72;
                            shortcutList.cancelFlick();
                            const maxY = Math.max(0, shortcutList.contentHeight - shortcutList.height);
                            shortcutList.contentY = Math.max(0, Math.min(maxY,
                                shortcutList.contentY - delta * 1.4));
                            event.accepted = true;
                        }
                    }
                    ScrollBar.vertical: ScrollBar {
                        id: shortcutScrollBar
                        width: 10
                        padding: 2
                        policy: ScrollBar.AsNeeded
                        background: Rectangle {
                            color: "#2c2c2f"
                            radius: width / 2
                        }
                        contentItem: Rectangle {
                            implicitWidth: 6
                            implicitHeight: 24
                            radius: width / 2
                            color: shortcutScrollBar.pressed ? "#a0a0a6" : "#707078"
                        }
                    }
                    Column {
                        id: helpColumn
                        width: shortcutList.width - 12
                        spacing: 8
                        Repeater {
                            model: win.shortcutDefinitions
                            delegate: Item {
                                id: shortcutRow
                                required property var modelData
                                width: helpColumn.width
                                height: Math.max(bindingFlow.implicitHeight, actionLabel.implicitHeight, 36)
                                Item {
                                    id: bindingFlow
                                    width: Math.min(230, shortcutRow.width * 0.46)
                                    implicitHeight: Math.max(bindingColumn.implicitHeight, 32)
                                    Column {
                                        id: bindingColumn
                                        width: implicitWidth
                                        spacing: 4
                                        Repeater {
                                            model: win.shortcutSequences(shortcutRow.modelData.id)
                                            delegate: Rectangle {
                                                id: bindingCell
                                                required property string modelData
                                                required property int index
                                                readonly property bool recording: win.recordingShortcut === shortcutRow.modelData.id
                                                    && win.recordingShortcutIndex === index
                                                onRecordingChanged: if (recording) Qt.callLater(() => win.ensureShortcutVisible(bindingCell))
                                                objectName: "shortcutBinding_" + shortcutRow.modelData.id + "_" + index
                                                width: Math.min(bindingFlow.width - 34, recording ? 90 : bindingLabel.implicitWidth + 40)
                                                height: Math.max(32, bindingLabel.implicitHeight + 12)
                                                radius: 5
                                                color: recording ? "#2c2c2f" : "transparent"
                                                border.width: recording ? 1 : 0
                                                border.color: win.accent
                                                Accessible.role: Accessible.Button
                                                Accessible.name: "Change " + shortcutRow.modelData.label + " shortcut " + win.shortcutDisplay(modelData)
                                                Label {
                                                    id: bindingLabel
                                                    objectName: "shortcutText_" + shortcutRow.modelData.id + "_" + bindingCell.index
                                                    anchors.centerIn: parent
                                                    anchors.horizontalCenterOffset: -10
                                                    text: bindingCell.recording ? "" : win.shortcutDisplay(bindingCell.modelData)
                                                    color: win.accent
                                                    font.pixelSize: 13
                                                    width: parent.width - 40
                                                    wrapMode: Text.WrapAnywhere
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: win.beginShortcutCapture(shortcutRow.modelData.id, bindingCell.index, bindingCell)
                                                }
                                                Rectangle {
                                                    objectName: "shortcutRemove_" + shortcutRow.modelData.id + "_" + bindingCell.index
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 3
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 22; height: 24; radius: 4
                                                    color: "#2c2c2f"
                                                    Accessible.role: Accessible.Button
                                                    Accessible.name: "Remove " + win.shortcutDisplay(bindingCell.modelData) + " shortcut for " + shortcutRow.modelData.label
                                                    Label { anchors.centerIn: parent; text: "−"; color: win.accent; font.pixelSize: 18 }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: win.removeShortcut(shortcutRow.modelData.id, bindingCell.index)
                                                    }
                                                }
                                            }
                                        }
                                        Rectangle {
                                            id: newBindingField
                                            objectName: "shortcutNew_" + shortcutRow.modelData.id
                                            visible: win.recordingShortcut === shortcutRow.modelData.id && win.recordingShortcutIndex < 0
                                            onVisibleChanged: if (visible) Qt.callLater(() => win.ensureShortcutVisible(newBindingField))
                                            width: 90; height: visible ? 32 : 0; radius: 5
                                            color: "#2c2c2f"; border.width: 1; border.color: win.accent
                                            MouseArea { anchors.fill: parent }
                                        }
                                    }
                                    Rectangle {
                                        objectName: "shortcutAdd_" + shortcutRow.modelData.id
                                        x: bindingColumn.width + 4
                                        width: 28; height: 32; radius: 5
                                        color: "#2c2c2f"
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Add shortcut for " + shortcutRow.modelData.label
                                        Label { anchors.centerIn: parent; text: "+"; color: win.accent; font.pixelSize: 20 }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: win.beginShortcutCapture(shortcutRow.modelData.id, -1, newBindingField)
                                        }
                                    }
                                }
                                Label {
                                    id: actionLabel
                                    objectName: "shortcutAction_" + shortcutRow.modelData.id
                                    anchors.left: bindingFlow.right
                                    anchors.leftMargin: 16
                                    anchors.top: parent.top
                                    anchors.topMargin: 8
                                    width: parent.width - bindingFlow.width - 16
                                    text: shortcutRow.modelData.label
                                    color: "#d6d6da"
                                    font.pixelSize: 13
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
                Button {
                    objectName: "shortcutReset"
                    text: "Reset defaults"
                    onClicked: {
                        win.cancelShortcutCapture();
                        shortcutStore.reset();
                        win.shortcutMessage = "Default shortcuts restored.";
                    }
                }
            }
            IconButton {
                objectName: "helpCloseButton"
                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 12
                width: 32; height: 32; radius: 16
                iconName: "close"
                tipText: "Close shortcuts"
                Accessible.role: Accessible.Button
                Accessible.name: "Close shortcuts"
                Accessible.onPressAction: win.helpVisible = false
                onClicked: win.helpVisible = false
            }
        }
    }

    // --- open confirmation (replacing an unexported edit) ---
    Rectangle {
        visible: win.openConfirmVisible
        anchors.fill: parent
        color: "#cc000000"
        onVisibleChanged: {
            if (visible)
                openKeepButton.forceActiveFocus();
        }

        MouseArea {
            anchors.fill: parent
            onClicked: win.openConfirmVisible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: openColumn.width + 64
            height: openColumn.height + 48
            radius: 12
            color: "#1c1c1e"

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: openColumn
                anchors.centerIn: parent
                spacing: 8

                Label {
                    text: "Unexported edit"
                    color: "white"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                Label {
                    text: "Opening another video will discard this edit. Open it anyway?"
                    color: "#d6d6da"
                    font.pixelSize: 13
                    bottomPadding: 12
                }

                Row {
                    anchors.right: parent.right
                    spacing: 10

                    DialogButton {
                        id: openKeepButton
                        text: "Keep editing"
                        KeyNavigation.left: openVideoConfirmButton
                        KeyNavigation.right: openVideoConfirmButton
                        KeyNavigation.tab: openVideoConfirmButton
                        KeyNavigation.backtab: openVideoConfirmButton
                        onClicked: win.openConfirmVisible = false
                    }
                    DialogButton {
                        id: openVideoConfirmButton
                        text: "Open video"
                        primary: true
                        KeyNavigation.left: openKeepButton
                        KeyNavigation.right: openKeepButton
                        KeyNavigation.tab: openKeepButton
                        KeyNavigation.backtab: openKeepButton
                        onClicked: {
                            win.openConfirmVisible = false;
                            backend.openVideoDialog();
                        }
                    }
                }
            }
        }
    }

    // --- quit confirmation ---
    Rectangle {
        visible: win.quitConfirmVisible
        anchors.fill: parent
        color: "#cc000000"
        onVisibleChanged: {
            if (visible)
                quitExportButton.forceActiveFocus();
        }

        MouseArea {
            anchors.fill: parent
            onClicked: win.quitConfirmVisible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: quitColumn.width + 64
            height: quitColumn.height + 48
            radius: 12
            color: "#1c1c1e"

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: quitColumn
                anchors.centerIn: parent
                spacing: 8

                Label {
                    text: "Unexported edit"
                    color: "white"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                Label {
                    text: "Your edit hasn't been exported. Quit anyway?"
                    color: "#d6d6da"
                    font.pixelSize: 13
                    bottomPadding: 12
                }

                Row {
                    anchors.right: parent.right
                    spacing: 10

                    DialogButton {
                        id: quitCancelButton
                        text: "Cancel"
                        KeyNavigation.left: quitExportButton
                        KeyNavigation.right: quitQuitButton
                        KeyNavigation.tab: quitQuitButton
                        KeyNavigation.backtab: quitExportButton
                        onClicked: win.quitConfirmVisible = false
                    }
                    DialogButton {
                        id: quitQuitButton
                        text: "Quit"
                        KeyNavigation.left: quitCancelButton
                        KeyNavigation.right: quitExportButton
                        KeyNavigation.tab: quitExportButton
                        KeyNavigation.backtab: quitCancelButton
                        onClicked: forceQuit()
                    }
                    DialogButton {
                        id: quitExportButton
                        text: "Export"
                        primary: true
                        KeyNavigation.left: quitQuitButton
                        KeyNavigation.right: quitCancelButton
                        KeyNavigation.tab: quitCancelButton
                        KeyNavigation.backtab: quitQuitButton
                        onClicked: {
                            win.quitConfirmVisible = false;
                            exportVideo();
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: backend
        function onInfoChanged() {
            win.edgeClip = -1;
            win.noticeText = "";
            noticeTimer.stop();
            // Drop any prime or load still pending for the last video.
            primeFallback.stop();
            player.priming = false;
            player.pendingMs = -1;
            // Load afresh, even the same path: it may be a new file now.
            player.source = "";
            editBar.zoomed = false;
            editBar.playheadSec = 0;
            if (win.hasVideo)
                player.show(0, 0, false);
        }
        function onExportDone(path) {
            win.showNotice("Saved " + path);
        }
        function onExportFailed(message) {
            win.showNotice("Export failed: " + message);
        }
        function onFrameSaved(path) {
            win.showNotice("Saved " + path);
        }
        function onFrameFailed(message) {
            win.showNotice("Could not save the frame: " + message);
        }
        function onLoadError(message) {
            // The export-reopen refusal is a complete sentence already.
            win.showNotice(message.startsWith("Saved") ? message : "Cannot open video: " + message);
        }
        function onSkippedVideos(count) {
            win.showNotice(count === 1 ? "Skipped a file that won't open." : "Skipped " + count + " files that won't open.");
        }
    }
}
