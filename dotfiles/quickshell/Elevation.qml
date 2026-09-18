import QtQuick.Effects

// The ONE drop shadow for floating shell surfaces (dock, panels, popups,
// toasts) — apply with:
//     layer.enabled: true
//     layer.effect: Elevation {}
//
// It is the `shadow-float` token and nothing else: 0 2px 6px, one short
// shadow, the colour and the offsets straight from Theme. Ewe has two
// shadows in total and no gloss; depth is a step of surface colour, and the
// shadow only says "this floats above your windows". MultiEffect pads the
// layer itself, so a host window only needs the shadow to fall inside its
// bounds (every popup window is full-screen and transparent).
MultiEffect {
    shadowEnabled: true
    shadowColor: Theme.shadowFloat.color
    shadowOpacity: 1.0                       // the token's colour carries the alpha
    shadowHorizontalOffset: Theme.shadowFloat.x
    shadowVerticalOffset: Theme.shadowFloat.y
    // MultiEffect's shadowBlur is a fraction of blurMax, so blurMax IS the
    // token's blur radius and the fraction stays 1.
    shadowBlur: 1.0
    blurMax: Theme.shadowFloat.blur
}
