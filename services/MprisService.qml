pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris

// Which MPRIS player the shell's now-playing widget is showing, and the
// paging between them.
//
// A singleton for the same reason NotificationService is one: this is
// cross-cutting state, not a property of a view. It used to live inside
// NotificationCenterPanel.qml — ~90 lines of player-selection policy in a
// window — which put this repo's own services/views split the wrong way
// round (services own state and I/O, views are thin readers). Nothing about
// "which player is selected" is specific to the control-center panel; if a
// second surface ever shows now-playing, it reads the same selection instead
// of forking its own.
//
// Deliberately thin: no filtering, no metadata smoothing, no pinning — this
// is a selection cursor over Mpris.players, not a media abstraction layer.
QtObject {
    id: root

    readonly property var players: Mpris.players.values

    // Which player the widget shows. Defaults to whichever's playing (or
    // index 0 if none are) the first time a player list actually exists;
    // after that it's just the user's own </> choice, clamped so it never
    // points past the end of a list that shrank.
    property int index: 0
    property bool indexInitialized: false

    readonly property var activePlayer: players.length > 0 ? players[Math.min(index, players.length - 1)] : null

    function defaultIndex() {
        for (let i = 0; i < root.players.length; i++) {
            if (root.players[i].isPlaying)
                return i;
        }
        return 0;
    }

    onPlayersChanged: {
        if (!indexInitialized && players.length > 0) {
            index = defaultIndex();
            indexInitialized = true;
        } else if (index >= players.length) {
            index = Math.max(0, players.length - 1);
        }
    }

    // Which way the now-playing card's content should slide — read by the
    // panel's slide spring, set here (not inferred from the index delta)
    // since wraparound at the ends of the list would otherwise make the
    // direction ambiguous.
    property int slideDirection: 1

    // The player the widget was just showing, captured right before `index`
    // changes below — the now-playing card renders this as a second,
    // non-interactive content layer sliding out while the new activePlayer's
    // content slides in, so a player switch reads as an actual transition
    // between two players' content instead of the single layer just jumping
    // straight to the new data mid-slide.
    property var previousPlayer: null

    // True for exactly the duration of the synchronous `index` write below —
    // Qt property notifies are direct/synchronous, so every dependent binding
    // and change handler downstream of that write (incl. the now-playing
    // card's track-change pop) reacts before the line after it runs. Lets the
    // card tell "track changed because the player was switched" (slide only)
    // apart from "track changed on the same player" (pop only) without a race
    // on which handler happens to fire first.
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
