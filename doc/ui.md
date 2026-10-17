# Scheme UI

`(ui core)` describes semantic controls as immutable `Ui Event` values and assigns
their rectangles in one top-down traversal. `(ui browser)` copies that result to
native browser buttons, text, meters, scroll regions and integer forms. The browser
owns focus and unfinished editing; the application reducer owns durable values.

This first slice follows the scoped horizontal/vertical layout and external-state
style of [Resin's archived GUI](https://github.com/tsnl/resin/blob/archive/main-v3/src/resin/gui.py)
and its [GLTF viewer](https://github.com/tsnl/resin/blob/archive/main-v3/apps/resin_editor/src/resin_editor/gltf_viewer.py).
It uses semantic DOM controls alongside the GPU viewport. Layout still runs in
Scheme: CSS does not measure children, allocate growth or solve constraints.

```scheme
(ui-row "choices" (grow 1) (px 48) 8
  (list
    (ui-button "less" (grow 1) (grow 1)
               "Decrease" "Keyboard and touch" #t #f (decrement))
    (ui-button "more" (grow 1) (grow 1)
               "Increase" "Enter activates focus" #t #t (increment))))
```

The requests above come from ordinary lexical `application` handlers. In the
presentation function, `(present-ui! (destination client-owner client-app) tree)`
ties all events to that application's owner and state types. The browser receives
versioned endpoint identities, never a user-maintained numeric command enum or a
live Wasm callback. Controls can also target a match destination directly; normal
game UI uses client handlers to retain its local selection behavior.

## Layout contract

Every node declares width and height as `(px pixels)` or `(grow weight)`. A row
allocates widths; a column allocates heights. The other axis fills available space
for `grow`, or clips a fixed size to the parent's available extent. Fixed sizes
clamp to 0–16384 and weights to 1–1024.

A parent reads only its immediate children's size declarations, subtracts fixed
sizes and gaps, then distributes the remaining pixels by weight. Rounding is
carried into the remaining allocation, so the last growing child receives the
remainder. It then visits each child exactly once with an assigned rectangle.
There is no recursive measurement pass, intrinsic content sizing, child-to-parent
feedback, cross-tree constraint, or ancestor relayout.

When fixed children and gaps exceed the parent, fixed sizes retain their declared
extent and growing sizes become zero. Rectangles never have negative dimensions.
Ordinary groups clip overflow. `ui-scroll` exposes a declared content extent in a
scroll region; keep essential controls outside that region. Text wraps inside its
allocated rectangle and clips excess lines. Applications choose a compact tree
for narrow screens; text does not implicitly enlarge it.

All constructors start with a stable, unique string key, width and height:

| Constructor | Remaining arguments |
| --- | --- |
| `ui-row`, `ui-column` | gap, children |
| `ui-panel` | padding, gap, children; vertical layout with panel background |
| `ui-scroll` | content height, gap, children; vertical scroll region |
| `ui-label` | text, tone |
| `ui-button` | text, help, enabled?, selected?, event |
| `ui-meter` | label, value, maximum, tone |
| `ui-number` | label, help, value, minimum, maximum, event template |

Tones are 0 normal, 1 subdued, 2 accent, 3 warning, 4 danger. `layout-ui` takes a
width, height and tree and returns a `Placement` tree for other renderers to consume.
The browser backend uses the allotted `[data-ui]` element's current dimensions.

## Editing and replacement

Stable keys retain the same DOM nodes across redraws and compatible module
replacement. Keyboard focus, a number field's unsubmitted text and scroll position
are browser-local transient state. Changing a key or control kind replaces that
control deliberately. Duplicate or missing keys reject the complete presentation
before it is published.

`ui-number` accepts a typed request template such as `(set-value 0)`. On submission
the browser replaces its first I32 argument with the parsed integer. That endpoint
must have exactly one I32 payload; the host checks this against the generated
manifest. Invalid or out-of-range text displays an accessible error and sends no
command. Other controls carry the supplied request unchanged.

Buttons support native Tab focus, Enter/Space activation, pointer and touch clicks.
Help is visible in a second line, available through native hover titles, and exposed
as an accessible description. This slice does not implement text editing beyond
integer forms, dropdowns, sliders, menus, drag/drop, or GPU-drawn widgets.

## Run the example

```sh
chibi-scheme -I bootstrap apps/ui-lab/build.scm "$PWD" "$PWD/build/ui-lab"
python3 -m http.server 4195 --directory build/ui-lab/solo
```

Open `http://localhost:4195`. This example selects the DOM renderer and needs no
WebGPU device. Its complete Scheme UI and reducers are in
`apps/ui-lab/src/ui-lab/game.sld`.

Browser checks use an isolated Chromium DevTools port and exercise real pointer,
keyboard, validation, focus preservation and compatible Wasm replacement:

```sh
node tests/ui/browser.mjs http://localhost:4195 http://localhost:9451 screenshot.png
```
