pragma ComponentBehavior: Bound
import QtQuick
import qs.shared

// Shared spring tuning for a module's implicitWidth easing (see Theme.qml's
// springSpring/springDamping for the empirical reasoning). Use as
// `Behavior on implicitWidth { WidthSpring {} }`.
SpringAnimation {
    spring: Theme.springSpring
    damping: Theme.springDamping
    epsilon: Theme.springEpsilon
}
