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

    // Defaults to whichever player is playing, then follows the user's </>
    // choice, clamped so it can't point past a list that shrank.
    property int index: 0
    property bool indexInitialized: false

    readonly property var activePlayer: players.length > 0 ? players[Math.min(index, players.length - 1)] : null

    // 0 when nothing is playing — findIndex's -1, clamped up.
    function defaultIndex() {
        return Math.max(0, root.players.findIndex(player => player.isPlaying));
    }

    onPlayersChanged: {
        if (!indexInitialized && players.length > 0) {
            index = defaultIndex();
            indexInitialized = true;
        } else if (index >= players.length) {
            index = Math.max(0, players.length - 1);
        }
    }

    // Which way the card's content slides. Set here because the index delta's
    // sign is ambiguous when the selection wraps.
    property int slideDirection: 1

    // The player just shown, captured before `index` changes: the card slides
    // it out as a second layer while the new one slides in.
    property var previousPlayer: null

    // True for exactly the `index` write below — notifies are synchronous, so
    // every downstream handler runs inside it. Lets the card tell a track
    // change caused by switching players (slide) from a real one (pop).
    property bool suppressPop: false

    function step(delta) {
        if (players.length === 0)
            return;
        slideDirection = delta;
        previousPlayer = activePlayer;
        suppressPop = true;
        index = (index + delta + players.length) % players.length;
        suppressPop = false;
    }

    function prev() {
        step(-1);
    }

    function next() {
        step(1);
    }
}
