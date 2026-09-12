pragma ComponentBehavior: Bound
import QtQuick
import qs.shared
import qs.shared.animations

// A spring-physics value driven by FrameAnimation, which ticks once per real
// rendered frame. Qt's own Behavior/SpringAnimation rides the shared
// QUnifiedTimer instead, fixed at ~60Hz regardless of the output's refresh
// rate — visibly stuttery on a 240Hz screen. See AGENTS.md's "capped near
// 60Hz" section. (Modelled on DankMaterialShell's Common/SpringMotion.qml.)
//
// Usage: bind the consuming property to `.value` and set `to`. The imperative
// snapTo()/retarget() API stays available for springs with no single resting
// expression (entry animations, direction-dependent slides).
QtObject {
    id: root

    // Set to a SpringGroup when this spring must stay visually locked to
    // others (e.g. Workspaces.qml's selection indicator and the delegate it
    // tracks). The group then owns the single FrameAnimation advancing all of
    // them by the identical dt; independent drivers measure elapsed time
    // separately, and that drift reads as wobble between parts meant to move
    // as one.
    property SpringGroup group: null
    onGroupChanged: if (group)
        group.add(root)
    // The group cannot detect this itself: a destroyed QObject isn't null from
    // JS, it's a wrapper that throws on access. See SpringGroup.remove().
    Component.onDestruction: if (group)
        group.remove(root)

    property real stiffness: Theme.frameSpringStiffness
    property real damping: Theme.frameSpringDamping
    property real mass: Theme.frameSpringMass
    property real epsilon: Theme.springEpsilon
    // Caps the per-tick step so a compositor hiccup can't fling the spring
    // through one huge integration step; long gaps are sub-stepped instead.
    property real maximumFrameTime: 1 / 30
    property real integrationStep: 1 / 240

    property real value: 0
    property real target: value
    property real velocity: 0
    property bool running: false

    // Declarative target: snaps to it on creation and retargets on every
    // later change, replacing the three-step manual ritual (bind `.value`,
    // snap in Component.onCompleted, retarget from onXChanged) — two steps of
    // which fail *silently* when forgotten, animating in from 0 on every
    // reload or freezing at the startup value forever.
    //
    // NaN is the "unset" sentinel, not 0: an imperatively-driven spring must
    // not have a resting target of 0 forced on it. Those leave `to` alone and
    // both handlers below do nothing. A call site's own Component.onCompleted
    // doesn't shadow this one — both run, base first.
    property real to: NaN
    onToChanged: if (!isNaN(to))
        retarget(to)
    Component.onCompleted: if (!isNaN(to))
        snapTo(to)

    function isSettled() {
        return Math.abs(target - value) <= epsilon && Math.abs(velocity) <= epsilon;
    }

    // Jumps straight to a value with no animation — for initial setup, not
    // mid-animation.
    function snapTo(v) {
        target = v;
        value = v;
        velocity = 0;
        running = false;
    }

    function retarget(v) {
        target = v;
        if (!isSettled())
            running = true;
    }

    function advance(rawFrameTime) {
        if (!running)
            return;

        const frameTime = Math.min(Math.max(rawFrameTime, 0), maximumFrameTime);
        if (frameTime <= 0)
            return;

        const steps = Math.max(1, Math.ceil(frameTime / integrationStep));
        const step = frameTime / steps;
        const inverseMass = 1 / Math.max(0.001, mass);

        for (let i = 0; i < steps; i++) {
            velocity += (stiffness * (target - value) - damping * velocity) * inverseMass * step;
            value += velocity * step;
        }

        if (isSettled()) {
            value = target;
            velocity = 0;
            running = false;
        }
    }

    // Gated on `running`, which advance() clears the moment the spring
    // settles: a live FrameAnimation re-renders and swaps a buffer every
    // frame for as long as it exists, animating or not. A grouped spring is
    // driven by its SpringGroup instead.
    property FrameAnimation driver: FrameAnimation {
        running: !root.group && root.running
        onTriggered: root.advance(frameTime)
    }
}
