pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire

// Default-sink volume and mute, shared by the bar module, the OSD and the
// `osd` IPC handler, and the default sink/source changes the OSD announces.
// A singleton so the PwObjectTracker keeping the sink's audio properties live
// exists once, not once per output.
QtObject {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool ready: nodeReady(sink)
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

    // The default sink and/or source moved to another device: the glyphs of
    // what moved, and its name(s). OsdService shows it. See notes/osd.md,
    // "Default audio device changes".
    signal defaultChanged(string glyph, string text)

    readonly property string sinkGlyph: "󰓃"
    readonly property string sourceGlyph: "󰍬"

    // Last default per direction, by node name: a PipeWire restart recreates
    // the objects under the same names. "" until one is first seen.
    property string lastSinkName: ""
    property string lastSinkLabel: ""
    property string lastSourceName: ""
    property string lastSourceLabel: ""

    // A default went null since the last adopt(): an unplug or a WirePlumber
    // restart, whose fallback may be a transient pick.
    property bool sawGap: false

    onSinkChanged: {
        if (!sink)
            sawGap = true;
        settle.restart();
    }
    onSourceChanged: {
        if (!source)
            sawGap = true;
        settle.restart();
    }
    // Catches a reload, where Pipewire is already up and nothing changes.
    Component.onCompleted: adopt(true)

    // A node's `ready` is only the core sync: one nothing tracked before has
    // no channel volumes until a tracker binds it, and reads as 0% meanwhile.
    function nodeReady(node) {
        return !!node && node.ready && !!node.audio && node.audio.volumes.length > 0;
    }

    // nickname is the short name ("SDAC"), set from the registry before the
    // node is bound, so no tracking is needed for it.
    function label(node) {
        return node.nickname || node.description || node.name;
    }

    // Records the current defaults, and unless `quiet`, announces those whose
    // device changed. A null default is skipped: it is the gap between an
    // unplug and WirePlumber's fallback, or a restart.
    function adopt(quiet) {
        const glyphs = [];
        const labels = [];
        if (sink && sink.name !== lastSinkName) {
            const text = label(sink);
            // A first sighting is a baseline; a new name under the same label
            // is the same device recreated.
            if (!quiet && lastSinkName !== "" && text !== lastSinkLabel) {
                glyphs.push(sinkGlyph);
                labels.push(text);
            }
            lastSinkName = sink.name;
            lastSinkLabel = text;
        }
        if (source && source.name !== lastSourceName) {
            const text = label(source);
            if (!quiet && lastSourceName !== "" && text !== lastSourceLabel) {
                glyphs.push(sourceGlyph);
                labels.push(text);
            }
            lastSourceName = source.name;
            lastSourceLabel = text;
        }
        // One headset's sink and source share a nickname; name it once.
        if (labels.length === 2 && labels[0] === labels[1])
            labels.pop();
        if (glyphs.length > 0)
            defaultChanged(glyphs.join(" "), labels.join("\u2003—\u2003"));
    }

    // One plug event moves the sink and the source a few ms apart; this makes
    // them one pill. After a gap it waits out WirePlumber's re-enumeration,
    // which can pick a fallback before the configured device exists. The
    // guards are read when it fires, not when it was armed.
    property Timer settle: Timer {
        interval: root.sawGap ? 1000 : 100
        onTriggered: {
            root.adopt(!Pipewire.ready || root.grace.running);
            root.sawGap = false;
        }
    }

    // Silent for a while after Pipewire (re)connects: WirePlumber can publish
    // the default late, or pick a fallback before a USB DAC enumerates.
    property Timer grace: Timer {
        interval: 2000
    }

    property Connections pipewire: Connections {
        target: Pipewire
        function onReadyChanged(): void {
            if (Pipewire.ready)
                root.grace.restart();
        }
    }
}
