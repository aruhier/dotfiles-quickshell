pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris

// Which MPRIS player the now-playing widget shows, and the paging between
// them. A selection cursor over Mpris.players, not a media abstraction; a
// singleton so a second surface would share the selection rather than fork it.
QtObject {
    id: root

    readonly property var players: Mpris.players.values

    // The player shown, not its position: a player quitting shifts the list,
    // and an index would silently land on another one. Picked when unset or
    // gone — whichever is playing, else the first — then follows </>.
    // A destroyed player nulls this `var` on its own.
    property var selected: null
    readonly property var activePlayer: selected
    // Its position, for the pager dots; -1 with no players.
    readonly property int index: players.indexOf(activePlayer)

    // 0 when nothing is playing — findIndex's -1, clamped up.
    function defaultIndex() {
        return Math.max(0, root.players.findIndex(player => player.isPlaying));
    }

    // Also at creation: the list it starts with fires no change.
    Component.onCompleted: pick()
    onPlayersChanged: pick()
    function pick() {
        if (root.selected !== null && root.players.indexOf(root.selected) !== -1)
            return;
        // A replacement isn't a new track on the same player: no pop.
        root.suppressPop = true;
        root.selected = root.players.length > 0 ? root.players[root.defaultIndex()] : null;
        root.suppressPop = false;
    }

    // Which way the card's content slides. Set here because the index delta's
    // sign is ambiguous when the selection wraps.
    property int slideDirection: 1

    // The player just shown, captured before the selection changes: the card slides
    // it out as a second layer while the new one slides in.
    property var previousPlayer: null

    // True for exactly the `selected` writes — notifies are synchronous, so
    // every downstream handler runs inside it. Lets the card tell a track
    // change caused by switching players (slide) from a real one (pop).
    property bool suppressPop: false

    function step(delta) {
        if (players.length === 0)
            return;
        slideDirection = delta;
        previousPlayer = activePlayer;
        suppressPop = true;
        selected = players[(Math.max(0, index) + delta + players.length) % players.length];
        suppressPop = false;
    }

    function prev() {
        step(-1);
    }

    function next() {
        step(1);
    }
}
