pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris

// Which MPRIS player the now-playing widget shows, and the paging between
// them. A singleton because this is cross-cutting state, not a property of one
// view: if a second surface ever shows now-playing it reads the same selection
// instead of forking its own.
//
// Deliberately thin — a selection cursor over Mpris.players, not a media
// abstraction layer.
QtObject {
    id: root

    readonly property var players: Mpris.players.values

    // Defaults to whichever player is playing (or 0 if none are) the first
    // time a player list exists. After that it's the user's own </> choice,
    // clamped so it never points past the end of a list that shrank.
    property int index: 0
    property bool indexInitialized: false

    readonly property var activePlayer: players.length > 0 ? players[Math.min(index, players.length - 1)] : null

    // 0 when nothing is playing, which is also findIndex's -1 clamped up.
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

    // Which way the now-playing card's content slides. Set here rather than
    // inferred from the index delta, whose sign is ambiguous when the
    // selection wraps around the ends of the list.
    property int slideDirection: 1

    // The player the widget was just showing, captured right before `index`
    // changes. The card renders it as a second, non-interactive layer sliding
    // out while the new player's content slides in, so a switch reads as a
    // transition rather than one layer jumping to new data mid-slide.
    property var previousPlayer: null

    // True for exactly the duration of the `index` write below. Qt property
    // notifies are synchronous, so every handler downstream of that write
    // (including the card's track-change pop) runs before the next line does.
    // Lets the card tell "track changed because the player was switched"
    // (slide only) from "track changed on the same player" (pop only).
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
