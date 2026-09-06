pragma ComponentBehavior: Bound
import QtQuick

// One FrameAnimation driving several FrameSprings that must advance by the
// *exact* same dt each tick to stay visually locked together (Workspaces.qml's
// pill, its delegates and its selection indicator — see that file). Set
// `group: someSpringGroup` on each FrameSpring instead of letting it run its
// own private FrameAnimation; springs register themselves here and this drives
// all of them from one `onTriggered`, so every one of them sees the identical
// `frameTime`.
//
// The driver is gated *declaratively* on "is any registered spring actually
// running", never started or stopped by hand. That's deliberate, and it is the
// whole reason this type exists rather than an ad-hoc FrameAnimation in the
// consuming file: a running FrameAnimation is a running QAbstractAnimation, so
// Qt Quick re-renders the scene graph and swaps a buffer *every frame* for as
// long as it lives, whether or not a pixel changed — an always-on driver cost
// a measured 7-8% of a core at idle on a 90Hz output (see INVEST.md). Binding
// `running` to the same state `advance()` clears means there is no way to
// forget to stop it, and no second place that has to know about every spring.
QtObject {
    id: group

    // Registered springs, in registration order. Reassigned (not mutated) on
    // every add/prune so bindings on it re-evaluate.
    property var springs: []

    function add(spring) {
        springs = springs.concat([spring]);
    }

    // Called from FrameSpring's own Component.onDestruction. This is not
    // optional bookkeeping: a destroyed QObject left in `springs` is *not*
    // null from JS — it's a stale wrapper that throws a TypeError on any
    // property access — so both `anyRunning` and the tick loop below would
    // start throwing every frame. It also emits no runningChanged, so a
    // spring destroyed mid-animation (workspace closed while its pill is
    // still easing) would strand `anyRunning` true and pin the driver on
    // forever. Removing here notifies `springs`, which re-evaluates
    // `anyRunning`, which stops the driver if that was the last one moving.
    function remove(spring) {
        springs = springs.filter(registered => registered !== spring);
    }

    // True while any registered spring still has motion left. Short-circuits,
    // which is safe: returning early on the first running spring means this
    // binding only depends on *that* spring's `running` until it goes false,
    // at which point it re-evaluates and picks up the rest.
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
