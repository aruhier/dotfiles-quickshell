pragma ComponentBehavior: Bound
import QtQuick

// One FrameAnimation driving several FrameSprings that must advance by the
// identical dt to stay visually locked (Workspaces.qml's pill, delegates and
// selection indicator). Springs join by setting `group: <this>`.
//
// The driver is gated on "is any registered spring running", never started by
// hand — that gating is why this type exists rather than an ad-hoc
// FrameAnimation: a live one re-renders the scene graph every frame whether or
// not a pixel changed, measured at 7-8% of a core at idle.
QtObject {
    id: group

    // Registered springs. Reassigned, not mutated, so bindings re-evaluate.
    property var springs: []

    function add(spring) {
        springs = springs.concat([spring]);
    }

    // Called from FrameSpring's Component.onDestruction, and not optional: a
    // destroyed QObject left here throws on every property access, and emits no
    // runningChanged — so it would both break the tick loop and strand
    // `anyRunning` true, pinning the driver on forever.
    function remove(spring) {
        springs = springs.filter(registered => registered !== spring);
    }

    // True while any registered spring still has motion left. Short-circuiting
    // is safe: the binding re-evaluates when that spring stops.
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
