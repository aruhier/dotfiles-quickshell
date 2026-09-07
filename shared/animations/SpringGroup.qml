pragma ComponentBehavior: Bound
import QtQuick

// One FrameAnimation driving several FrameSprings that must advance by the
// identical dt each tick to stay visually locked together (Workspaces.qml's
// pill, delegates and selection indicator). Springs join by setting
// `group: <this>` and are all advanced from one `onTriggered`.
//
// The driver is gated declaratively on "is any registered spring running",
// never started or stopped by hand — that gating is the reason this type
// exists rather than an ad-hoc FrameAnimation in the consuming file. A live
// FrameAnimation re-renders the scene graph every frame whether or not a
// pixel changed; an always-on one measured 7-8% of a core at idle.
QtObject {
    id: group

    // Registered springs. Reassigned, not mutated, so bindings re-evaluate.
    property var springs: []

    function add(spring) {
        springs = springs.concat([spring]);
    }

    // Called from FrameSpring's Component.onDestruction, and not optional: a
    // destroyed QObject left in `springs` is not null from JS but a stale
    // wrapper that throws on any property access, so both `anyRunning` and the
    // tick loop would throw every frame. It also emits no runningChanged, so a
    // spring destroyed mid-animation would strand `anyRunning` true and pin
    // the driver on forever.
    function remove(spring) {
        springs = springs.filter(registered => registered !== spring);
    }

    // True while any registered spring still has motion left. Short-circuits
    // safely: the binding then depends only on that spring's `running` until
    // it goes false, at which point it re-evaluates and picks up the rest.
    readonly property bool anyRunning: {
        const list = group.springs;
        for (let i = 0; i < list.length; i++) {
            if (list[i].running)
                return true;
        }
        return false;
    }

    property FrameAnimation driver: FrameAnimation {
        running: group.anyRunning
        onTriggered: {
            const list = group.springs;
            for (let i = 0; i < list.length; i++)
                list[i].advance(frameTime);
        }
    }
}
