pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io

// Shared backlight state, with exponential perceptual scaling.
//
// Reads come straight out of /sys/class/backlight: a FolderListModel finds the
// device, FileViews read max_brightness/brightness, and an inotify watch on
// `brightness` reports external changes — nothing polls or forks. Writes go
// through brightnessctl (the sysfs node is root-owned, which is what its
// setuid/logind helper is for), but only on an actual user action.
QtObject {
    id: root

    // Perceptual position of the backlight, 0..100 — see `exponent`.
    readonly property real percent: available ? Math.pow(linear, 1.0 / exponent) * 100 : 0
    readonly property bool available: device !== "" && maxRaw > 0
    readonly property real linear: maxRaw > 0 ? Math.max(0, Math.min(1, raw / maxRaw)) : 0

    // percent = (raw / maxRaw) ^ (1 / exponent). 4 is what `brightnessctl -e`
    // uses when given no K, so a "+10%" there and a 10-point move here are
    // the same raw change; keep them in sync if either side changes.
    property real exponent: 4

    // One wheel notch, in perceptual units (0..1).
    property real step: 0.05

    // Never write 0: that switches the panel off and only another backlight
    // write brings it back. Same default as brightnessctl's --min-value.
    readonly property int minRaw: 1

    // sysfs device name, e.g. "intel_backlight". Empty until discovery runs,
    // and stays empty on a machine with no backlight.
    property string device: ""
    readonly property string devicePath: device === "" ? "" : "/sys/class/backlight/" + device
    property int maxRaw: 0
    property int raw: 0

    // Latest value asked for while a brightnessctl write is already in
    // flight, -1 when nothing is queued: spinning the wheel outruns process
    // spawns, and exec() on a running Process is not a queue.
    property int pendingRaw: -1

    // Move `steps` wheel notches up (positive) or down (negative).
    function bump(steps) {
        if (!available)
            return;
        const target = Math.max(0, Math.min(1, Math.pow(linear, 1.0 / exponent) + steps * step));
        let next = Math.round(maxRaw * Math.pow(target, exponent));
        // At the dark end a whole perceptual step can be worth less than one
        // raw unit, and rounding would swallow it, leaving the wheel dead.
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

    // Prefer a real panel backlight: nvidia's stub and acpi_video's mirror of
    // another device both show up here on some machines, and neither is the
    // one to drive when a native device exists.
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

    // Entries are symlinks into /sys/devices/…; QDir follows them, so they
    // list as directories.
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

    // watchChanges, not a poll timer: sysfs backlight attributes call
    // sysfs_notify() on change and kernfs raises a real fsnotify FS_MODIFY
    // from that, so an inotify watch on this pseudo-file does fire — hardware
    // keys and brightnessctl keybinds land here immediately. (Verified with
    // both inotifywait and a standalone FileView probe.)
    //
    // reload() is explicit because FileView doesn't re-read on its own. The
    // parse stays in onLoaded, which fires on every reload even when the bytes
    // are identical.
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
            // Resync: brightnessctl clamps and the driver quantizes, so what
            // landed isn't necessarily what was asked for.
            root.refresh();
            root.flush();
        }
    }
}
