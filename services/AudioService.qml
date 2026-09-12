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
    readonly property bool ready: !!sink && sink.ready && !!sink.audio
    readonly property bool muted: ready && sink.audio.muted
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property int pct: Math.round(volume * 100)

    // The ceiling the old swayosd-client binds ran at (its own default), and
    // what the wheel on the bar module has always clamped to.
    readonly property int maxPct: 100

    // Muted replaces the whole format on the bar: icon only, no percent.
    readonly property string icon: muted ? "󰝟" : pct < 33 ? "󰕿" : pct < 66 ? "󰖀" : "󰕾"

    function setPct(value) {
        if (ready)
            sink.audio.volume = Math.max(0, Math.min(maxPct, Math.round(value))) / 100;
    }

    function bumpPct(delta) {
        setPct(pct + delta);
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
