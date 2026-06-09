import QtQuick
import qs.modules.ephemera.port.Common

// Reusable ColorAnimation wrapper
ColorAnimation {
    duration: Theme.expressiveDurations.normal
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.expressiveCurves.standard
}
