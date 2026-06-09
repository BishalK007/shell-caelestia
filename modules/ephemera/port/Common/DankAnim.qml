import QtQuick
import qs.modules.ephemera.port.Common

// Reusable NumberAnimation wrapper
NumberAnimation {
    duration: Theme.expressiveDurations.normal
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.expressiveCurves.standard
}
