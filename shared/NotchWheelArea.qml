pragma ComponentBehavior: Bound
import QtQuick

// A MouseArea that turns vertical wheel input into whole notches. High-res
// wheels and touchpads send fractions of a 120-unit notch per event, so each
// event can't be a step; horizontal scroll (y == 0) is ignored.
MouseArea {
    id: root

    // `notches` is signed: positive is up / away from the user.
    signal stepped(int notches)

    property real pending: 0

    onWheel: (event) => {
        const dy = event.angleDelta.y;
        if (dy === 0)
            return;
        // Reversing drops what was left over from the other direction.
        if (root.pending !== 0 && (dy > 0) !== (root.pending > 0))
            root.pending = 0;
        root.pending += dy;
        const notches = Math.trunc(root.pending / 120);
        if (notches === 0)
            return;
        root.pending -= notches * 120;
        root.stepped(notches);
    }
}
