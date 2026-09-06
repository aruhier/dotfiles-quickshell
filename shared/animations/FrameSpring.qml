import QtQuick
import ".."

// A spring-physics value driven by FrameAnimation (ticks once per actual
// rendered frame, tied to the window's real vsync/frame-swap cadence)
// instead of Behavior/SpringAnimation, which rides Qt Quick's shared
// QUnifiedTimer GUI-thread clock — that clock ticks at a fixed ~60Hz
// regardless of the output's real refresh rate, so a Behavior-based spring
// on a high refresh-rate screen (this machine's DP-1 runs 240Hz) visibly
// stutters even though the compositor could show far smoother motion. See
// AGENT.md's "Spring/Behavior animations are capped near 60Hz" section for
// how that was empirically confirmed (QSG_RENDER_TIMING=1 showed a steady
// ~16ms cadence on the notification panel's window regardless of the
// output's real rate, unaffected by QSG_FIXED_ANIMATION_STEP). Modeled on
// DankMaterialShell's Common/SpringMotion.qml, which uses this exact
// FrameAnimation-driven approach.
//
// Unlike Behavior/SpringAnimation, this isn't declarative — there's no
// "animate whenever this expression changes" wiring. Bind the consuming
// property to `.value` and call `retarget(newTarget)` imperatively when
// the desired value changes (e.g. from a Connections handler), same as
// DankMaterialShell's usage.
//
// stiffness/damping/mass default to Hyprland's own spring config, unlike
// Theme.qml's springSpring/springDamping — those are tuned for Qt's
// SpringAnimation, which (per Theme.qml's comment) does NOT share
// Hyprland's unit convention despite the same underlying mass-spring-damper
// ODE shape. This type implements that ODE directly, so Hyprland's actual
// physical constants are the correct values to start from here.
QtObject {
    id: root

    // Set to a SpringGroup for a spring that's one of several coupled values
    // that all need to move by the *exact same* dt each tick to stay
    // visually locked together (e.g. Workspaces.qml's sliding selection
    // indicator and the delegate it tracks). The group then owns the one
    // FrameAnimation that advances all of its springs, and this spring runs
    // no driver of its own. Left null, each FrameSpring owns an independent
    // FrameAnimation, and independent instances measure their own elapsed
    // time separately; on a very high refresh-rate output that per-instance
    // timing skew (confirmed empirically: two standalone springs chasing the
    // same target reported values differing in the 2nd decimal place at the
    // "same" moment) is small in absolute terms but enough, compounded
    // across several coupled springs, to read as visible wobble between
    // parts that are supposed to move as one. See AGENT.md's Workspaces.qml
    // section.
    property SpringGroup group: null
    onGroupChanged: if (group)
        group.add(root)
    // Must unregister: the group can't detect this on its own, since a
    // destroyed QObject is not null from JS, it's a wrapper that throws on
    // access. See SpringGroup.remove().
    Component.onDestruction: if (group)
        group.remove(root)

    property real stiffness: Theme.frameSpringStiffness
    property real damping: Theme.frameSpringDamping
    property real mass: Theme.frameSpringMass
    property real epsilon: Theme.springEpsilon
    // Caps the per-tick integration step so a stall (e.g. a compositor
    // hiccup) can't fling the spring through a huge single step; large
    // frame gaps are instead integrated over several smaller sub-steps
    // below.
    property real maximumFrameTime: 1 / 30
    property real integrationStep: 1 / 240

    property real value: 0
    property real target: value
    property real velocity: 0
    property bool running: false

    function isSettled() {
        return Math.abs(target - value) <= epsilon && Math.abs(velocity) <= epsilon;
    }

    // Jumps straight to a value with no animation — for initial setup, not
    // for use mid-animation.
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
    // settles — a FrameAnimation left running re-renders and swaps a buffer
    // every frame for as long as it lives, whatever it's animating. A
    // grouped spring is driven by its SpringGroup instead; see that file.
    property FrameAnimation driver: FrameAnimation {
        running: !root.group && root.running
        onTriggered: root.advance(frameTime)
    }
}
