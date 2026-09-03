import QtQuick.Effects

// The ONE drop-shadow recipe for floating shell surfaces (dock, panels,
// popups, toasts) — apply with:
//     layer.enabled: true
//     layer.effect: Elevation {}
// Keeping the numbers here means every surface lifts off the desktop the
// same way; tweak the feel once, not per component. MultiEffect pads the
// layer automatically, so the host window only needs the shadow to fall
// inside its bounds (all popup windows are full-screen and transparent).
// The two looks disagree about what depth IS, so the recipe forks here rather
// than at 40 call sites. Alexandria lifts a surface with ambient blur; Bauhaus
// forbids soft shadows outright and gets its depth from a hard block of solid
// colour offset down-right (Theme.shadowOffset). Same three lines at every
// call site, opposite result.
MultiEffect {
    shadowEnabled: true
    shadowColor: Theme.shadow
    shadowOpacity: Theme.brutalist ? 1.0 : 0.65
    shadowBlur: Theme.brutalist ? 0.0 : 1.0
    shadowHorizontalOffset: Theme.brutalist ? Theme.shadowOffset : 0
    shadowVerticalOffset: Theme.brutalist ? Theme.shadowOffset : 7
    blurMax: 48
}
