pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io

// Shared backlight state, with exponential perceptual scaling. Reads come
// straight out of /sys/class/backlight — device discovery, the two values, and
// an inotify watch for external changes, with nothing polling or forking.
// Writes go through brightnessctl, since the sysfs node is root-owned.
QtObject {
    id: root

    // Perceptual position of the backlight, 0..100 — see `exponent`.
    readonly property real percent: available ? Math.pow(linear, 1.0 / exponent) * 100 : 0
    readonly property bool available: device !== "" && maxRaw > 0
    readonly property real linear: maxRaw > 0 ? Math.max(0, Math.min(1, raw / maxRaw)) : 0

    // percent = (raw / maxRaw) ^ (1 / exponent). 4 matches `brightnessctl -e`,
    // so a "+10%" there and a 10-point move here are the same raw change.
    property real exponent: 4

    // One wheel notch, in perceptual units (0..1).
    property real step: 0.05

    // Never write 0 — that switches the panel off, and only another backlight
    // write brings it back.
    readonly property int minRaw: 1

    // e.g. "intel_backlight". Empty until discovery runs, and on a machine
    // with no backlight.
    property string device: ""
    readonly property string devicePath: device === "" ? "" : "/sys/class/backlight/" + device
    property int maxRaw: 0
    property int raw: 0

    // Latest value asked for while a write is in flight, -1 when idle:
    // spinning the wheel outruns process spawns, and exec() isn't a queue.
    property int pendingRaw: -1

    // Move `steps` wheel notches up (positive) or down (negative).
    function bump(steps) {
        if (!available)
            return;
        const target = Math.max(0, Math.min(1, Math.pow(linear, 1.0 / exponent) + steps * step));
        let next = Math.round(maxRaw * Math.pow(target, exponent));
        // At the dark end a perceptual step can be worth under one raw unit,
        // and rounding would swallow it, leaving the wheel dead.
        if (next === raw)
            next = raw + (steps > 0 ? 1 : -1);
        setRaw(next);
    }

    function setRaw(value) {
        const clamped = Math.max(minRaw, Math.min(maxRaw, Math.round(value)));
        if (clamped === raw)
            return;
        // Optimistic: the label follows the wheel now, not one poll later.
        raw = clamped;
        pendingRaw = clamped;
        flush();
    }

    function flush() {
        if (pendingRaw < 0 || setProc.running)
            return;
        const value = pendingRaw;
        pendingRaw = -1;
        setProc.exec(["brightnessctl", "-d", root.device, "-q", "set", String(value)]);
    }

    function refresh() {
        if (device !== "")
            brightnessFile.reload();
    }

    // Prefer a real panel backlight: nvidia's stub and acpi_video's mirror
    // also show up here, and neither is the one to drive.
    function rank(name) {
        if (name.startsWith("nvidia"))
            return 2;
        if (name.startsWith("acpi_video"))
            return 1;
        return 0;
    }

    function pickDevice() {
        let best = "";
        for (let i = 0; i < devices.count; i++) {
            const name = devices.get(i, "fileName");
            if (best === "" || rank(name) < rank(best))
                best = name;
        }
        return best;
    }

    // Entries are symlinks into /sys/devices/…, which QDir lists as dirs.
    property FolderListModel devices: FolderListModel {
        id: devices
        folder: "file:///sys/class/backlight"
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        onStatusChanged: if (status === FolderListModel.Ready)
            root.device = root.pickDevice()
    }

    property FileView maxFile: FileView {
        id: maxFile
        path: root.devicePath === "" ? "" : root.devicePath + "/max_brightness"
        onLoaded: root.maxRaw = parseInt(text().trim()) || 0
        onLoadFailed: root.maxRaw = 0
    }

    // watchChanges, not a poll timer: sysfs backlight attributes do raise a
    // real inotify event, so hardware keys and external writes land here
    // immediately. reload() is explicit — FileView doesn't re-read on its own
    // — and onLoaded fires on every reload, identical bytes included.
    property FileView brightnessFile: FileView {
        id: brightnessFile
        path: root.devicePath === "" ? "" : root.devicePath + "/brightness"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.raw = parseInt(text().trim()) || 0
    }

    property Process setProc: Process {
        id: setProc
        onExited: {
            // Resync: the write is clamped and quantized on the way down.
            root.refresh();
            root.flush();
        }
    }
}
