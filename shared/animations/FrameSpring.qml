pragma ComponentBehavior: Bound
import QtQuick
import qs.shared.animations
import qs.themes

// A spring-physics value driven by FrameAnimation, ticking once per rendered
// frame. Qt's own Behavior/SpringAnimation rides a shared timer fixed near
// 60Hz whatever the output does, which is visibly stuttery at 240Hz; see
// notes/rendering.md's "capped near 60Hz" section.
//
// Usage: bind the consuming property to `.value` and set `to`. The imperative
// snapTo()/retarget() API stays for springs with no single resting expression
// (entry animations, direction-dependent slides).
QtObject {
    id: root

    // Set when this spring must stay locked to others (Workspaces.qml's
    // selection indicator and its delegate). The group's single FrameAnimation
    // advances them all by the identical dt; independent drivers drift, and
    // that reads as wobble between parts meant to move as one.
    property SpringGroup group: null
    onGroupChanged: if (group)
        group.add(root)
    // The group can't detect this itself: a destroyed QObject isn't null from
    // JS, it's a wrapper that throws on access. See SpringGroup.remove().
    Component.onDestruction: if (group)
        group.remove(root)

    // Constants of the mass-spring-damper ODE integrated below. Defaults
    // for every module's width easing; callers with their own tuning override
    // them (WorkspaceFrameSpring.qml).
    property real stiffness: 460
    property real damping: 35
    property real mass: 0.6
    property real epsilon: Theme.springEpsilon
    // Caps the per-tick step so a compositor hiccup can't fling the spring in
    // one huge leap: a longer gap is clamped, not caught up, so a 200ms stall
    // advances the spring 33ms. The sub-stepping below is for accuracy within
    // a tick, not for covering gaps.
    property real maximumFrameTime: 1 / 30
    property real integrationStep: 1 / 240

    property real value: 0
    property real target: value
    property real velocity: 0
    property bool running: false

    // Declarative target: snaps on creation, retargets on every later change.
    // The manual equivalent (snap in Component.onCompleted, retarget from
    // onXChanged) fails silently when half-done — animating in from 0 on every
    // reload, or frozen at the startup value.
    //
    // NaN, not 0, is the unset sentinel: an imperatively-driven spring must not
    // be forced to rest at 0. Those leave `to` alone and both handlers below do
    // nothing. A call site's own Component.onCompleted doesn't shadow this one.
    property real to: NaN
    onToChanged: if (!isNaN(to))
        retarget(to)
    Component.onCompleted: if (!isNaN(to))
        snapTo(to)

    function isSettled() {
        return Math.abs(target - value) <= epsilon && Math.abs(velocity) <= epsilon;
    }

    // For initial setup, not mid-animation.
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

    // Gated on `running`: a live FrameAnimation re-renders and swaps a buffer
    // every frame for as long as it exists, animating or not. A grouped spring
    // is driven by its SpringGroup instead.
    property FrameAnimation driver: FrameAnimation {
        running: !root.group && root.running
        onTriggered: root.advance(frameTime)
    }
}
