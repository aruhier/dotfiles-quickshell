pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire

// Which apps are capturing the mic, the screen or the camera, from a scan of
// Pipewire's nodes. A singleton so the tracker binding every node exists
// once, not once per bar that lists `privacy`. Quickshell's PwNode can't tell
// an open stream from a RUNNING one, so open counts. See notes/privacy.md.
QtObject {
    id: root

    // Every `properties` read below needs this: an untracked node never gets
    // its properties bound, whatever its media class.
    property PwObjectTracker nodeTracker: PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    // Pipewire booleans: "true" from pipewire-pulse, "1" is as valid.
    function flag(value) {
        return value === "true" || value === "1";
    }

    // Not every record stream is a mic. Skips sink/monitor recordings and
    // meters, and in-graph plumbing (link group). See notes/privacy.md.
    function isMicCapture(props) {
        // Exact: a headset's permanent `…/Audio/Internal` node isn't a mic.
        if (props["media.class"] !== "Stream/Input/Audio")
            return false;
        if (root.flag(props["stream.capture.sink"]) || root.flag(props["stream.monitor"]))
            return false;
        if (props["media.category"] === "Monitor" || props["media.category"] === "Manager")
            return false;
        return !props["node.link-group"];
    }

    // A camera is a v4l2/libcamera device node (not "alsa", which audio
    // devices carry); a screencast is a portal's client stream. The name is
    // read from the registry, so it's there before props bind.
    function isCamera(node) {
        const api = (node.properties || {})["device.api"];
        return api === "v4l2" || api === "libcamera" || /^(v4l2|libcamera)_input\./.test(node.name || "");
    }

    // What each video consumer is linked from, keyed by consumer node id.
    // Link groups are process-wide and their ends constant: no tracker needed.
    readonly property var videoSources: {
        const byTarget = {};
        const groups = Pipewire.linkGroups.values;
        for (let i = 0; i < groups.length; i++) {
            const g = groups[i];
            if (!g.source || !g.target || (g.target.properties || {})["media.class"] !== "Stream/Input/Video")
                continue;
            const id = g.target.id;
            if (!byTarget[id])
                byTarget[id] = {};
            byTarget[id][root.isCamera(g.source) ? "camera" : "screen"] = true;
        }
        return byTarget;
    }

    // One row per capturing app, merging its nodes, so a call doing several
    // is one row with several glyphs.
    readonly property var capturingApps: {
        const nodes = Pipewire.nodes.values;
        const apps = [];
        const indexByKey = {};
        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            const props = node.properties || {};
            const mic = root.isMicCapture(props);
            const video = props["media.class"] === "Stream/Input/Video" ? (root.videoSources[node.id] ?? {}) : {};
            if (!mic && !video.screen && !video.camera)
                continue;
            // One app's streams disagree on case (Firefox reports "Firefox"
            // on mic, "firefox" on video), so fold it to merge them.
            const reported = props["application.name"] || "";
            const key = (reported || node.name || "Unknown").toLowerCase();
            let app = apps[indexByKey[key]];
            if (app === undefined) {
                indexByKey[key] = apps.length;
                app = {
                    name: reported || node.name || "Unknown",
                    // Folded key, not the label: icon names are lowercase.
                    icon: key,
                    mic: false,
                    screen: false,
                    camera: false
                };
                apps.push(app);
            }
            // A later node may know better than the first one seen.
            if (reported)
                app.name = reported;
            if (props["application.icon-name"])
                app.icon = props["application.icon-name"];
            app.mic = app.mic || mic;
            app.screen = app.screen || !!video.screen;
            app.camera = app.camera || !!video.camera;
        }
        return apps;
    }

    readonly property bool micActive: capturingApps.some(app => app.mic)
    readonly property bool screenActive: capturingApps.some(app => app.screen)
    readonly property bool cameraActive: capturingApps.some(app => app.camera)
    // A row only exists with at least one flag set.
    readonly property bool anyActive: capturingApps.length > 0
}
