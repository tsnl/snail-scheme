;; The page's screen, as host/browser/host.mjs provides it: one import per
;; drawing command, each taking scalars. (snail shell app)'s `screen` effect
;; defaults to these.
(define-library (snail runtime browser screen)
  (export
   frame-begin
   camera
   light
   picture-begin
   layer
   source-begin
   source-word
   swap
   picture-end
   batch-begin
   instance
   surface
   frame-end
   hud-begin
   panel-begin
   widget-begin
   widget-image
   field
   text-character
   hud-end)
  (import
   (snail core base))
  (begin
    (extern frame-begin "snail.runtime.browser.screen" "frame-begin" (Fn I32 F32 → Unit))
    (extern camera
            "snail.runtime.browser.screen"
            "camera"
            (Fn F32 F32 F32 F32 F32 F32 I32 F32 → Unit))
    (extern light "snail.runtime.browser.screen" "light" (Fn F32 F32 F32 F32 F32 → Unit))
    (extern picture-begin
            "snail.runtime.browser.screen"
            "picture-begin"
            (Fn I32 I32 I32 I32 → Bool))
    (extern layer
            "snail.runtime.browser.screen"
            "layer"
            (Fn I32 I32 I32 I32 I32 I32 I32 → Bool))
    (extern source-begin "snail.runtime.browser.screen" "source-begin" (Fn I32 I32 → Unit))
    (extern source-word "snail.runtime.browser.screen" "source-word" (Fn I32 → Unit))
    (extern swap "snail.runtime.browser.screen" "swap" (Fn I32 I32 → Unit))
    (extern picture-end "snail.runtime.browser.screen" "picture-end" (Fn → Unit))
    (extern batch-begin
            "snail.runtime.browser.screen"
            "batch-begin"
            (Fn I32 I32 I32 F32 F32 F32 F32 → Bool))
    (extern instance
            "snail.runtime.browser.screen"
            "instance"
            (Fn I32 F32 F32 F32 F32 F32 F32 F32 I32 F32 F32 F32 F32 → Unit))
    (extern surface
            "snail.runtime.browser.screen"
            "surface"
            (Fn F32 F32 I32 I32 I32 I32 I32 I32 I32 I32 → Unit))
    (extern frame-end "snail.runtime.browser.screen" "frame-end" (Fn → Unit))
    (extern hud-begin "snail.runtime.browser.screen" "hud-begin" (Fn → Unit))
    (extern panel-begin
            "snail.runtime.browser.screen"
            "panel-begin"
            (Fn I32 I32 I32 I32 → Unit))
    (extern widget-begin
            "snail.runtime.browser.screen"
            "widget-begin"
            (Fn I32 I32 I32 I32 I32 F32 → Unit))
    (extern widget-image
            "snail.runtime.browser.screen"
            "widget-image"
            (Fn I32 I32 I32 I32 I32 I32 → Unit))
    (extern field "snail.runtime.browser.screen" "field" (Fn I32 → Unit))
    (extern text-character "snail.runtime.browser.screen" "text-character" (Fn Char → Unit))
    (extern hud-end "snail.runtime.browser.screen" "hud-end" (Fn → Unit))))
