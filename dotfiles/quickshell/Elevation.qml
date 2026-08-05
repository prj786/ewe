import QtQuick.Effects

// The ONE drop-shadow recipe for floating shell surfaces (dock, panels,
// popups, toasts) — apply with:
//     layer.enabled: true
//     layer.effect: Elevation {}
// Keeping the numbers here means every surface lifts off the desktop the
// same way; tweak the feel once, not per component. MultiEffect pads the
// layer automatically, so the host window only needs the shadow to fall
// inside its bounds (all popup windows are full-screen and transparent).
MultiEffect {
    shadowEnabled: true
    shadowColor: Theme.shadow
    shadowOpacity: 0.65
    shadowBlur: 1.0
    shadowVerticalOffset: 7
    blurMax: 48
}
