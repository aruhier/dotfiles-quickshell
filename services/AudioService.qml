pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire

// Default-sink volume and mute, shared by the bar module, the OSD and the
// `osd` IPC handler. A singleton so the PwObjectTracker keeping the sink's
// audio properties live exists once, not once per output.
QtObject {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    // `ready` is only the core sync: a sink nothing tracked before has no
    // channel volumes until the tracker binds it, and reads as 0% meanwhile.
    readonly property bool ready: !!sink && sink.ready && !!sink.audio && sink.audio.volumes.length > 0
    readonly property bool muted: ready && sink.audio.muted
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property int pct: Math.round(volume * 100)

    // No boost past this from here; the OSD's bar is scaled to it.
    readonly property int maxPct: 100

    readonly property string icon: muted ? "󰝟" : pct < 33 ? "󰕿" : pct < 66 ? "󰖀" : "󰕾"

    // A volume already past maxPct (set in pavucontrol, say) is kept as the
    // ceiling: up must never lower it, and down steps from where it is.
    function bumpPct(delta) {
        if (!ready)
            return;
        const ceiling = Math.max(maxPct, pct);
        sink.audio.volume = Math.max(0, Math.min(ceiling, Math.round(pct + delta))) / 100;
    }

    function toggleMute() {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }

    // Without this the sink's volume/muted never update: Pipewire only binds
    // an object's properties while something tracks it.
    property PwObjectTracker tracker: PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }
}
