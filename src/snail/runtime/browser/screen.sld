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
    (extern frame-begin "snail.runtime.browser.screen" "frame-begin" (impl (Fn I32 F32 -> Unit)))
    (extern camera
            "snail.runtime.browser.screen"
            "camera"
            (impl (Fn F32 F32 F32 F32 F32 F32 I32 F32 -> Unit)))
    (extern light "snail.runtime.browser.screen" "light" (impl (Fn F32 F32 F32 F32 F32 -> Unit)))
    (extern picture-begin
            "snail.runtime.browser.screen"
            "picture-begin"
            (impl (Fn I32 I32 I32 I32 -> Bool)))
    (extern layer
            "snail.runtime.browser.screen"
            "layer"
            (impl (Fn I32 I32 I32 I32 I32 I32 I32 -> Bool)))
    (extern source-begin "snail.runtime.browser.screen" "source-begin" (impl (Fn I32 I32 -> Unit)))
    (extern source-word "snail.runtime.browser.screen" "source-word" (impl (Fn I32 -> Unit)))
    (extern swap "snail.runtime.browser.screen" "swap" (impl (Fn I32 I32 -> Unit)))
    (extern picture-end "snail.runtime.browser.screen" "picture-end" (impl (Fn -> Unit)))
    (extern batch-begin
            "snail.runtime.browser.screen"
            "batch-begin"
            (impl (Fn I32 I32 I32 F32 F32 F32 F32 -> Bool)))
    (extern instance
            "snail.runtime.browser.screen"
            "instance"
            (impl (Fn I32 F32 F32 F32 F32 F32 F32 F32 I32 F32 F32 F32 F32 -> Unit)))
    (extern surface
            "snail.runtime.browser.screen"
            "surface"
            (impl (Fn F32 F32 I32 I32 I32 I32 I32 I32 I32 I32 -> Unit)))
    (extern frame-end "snail.runtime.browser.screen" "frame-end" (impl (Fn -> Unit)))
    (extern hud-begin "snail.runtime.browser.screen" "hud-begin" (impl (Fn -> Unit)))
    (extern panel-begin
            "snail.runtime.browser.screen"
            "panel-begin"
            (impl (Fn I32 I32 I32 I32 -> Unit)))
    (extern widget-begin
            "snail.runtime.browser.screen"
            "widget-begin"
            (impl (Fn I32 I32 I32 I32 I32 F32 -> Unit)))
    (extern widget-image
            "snail.runtime.browser.screen"
            "widget-image"
            (impl (Fn I32 I32 I32 I32 I32 I32 -> Unit)))
    (extern field "snail.runtime.browser.screen" "field" (impl (Fn I32 -> Unit)))
    (extern text-character "snail.runtime.browser.screen" "text-character" (impl (Fn Char -> Unit)))
    (extern hud-end "snail.runtime.browser.screen" "hud-end" (impl (Fn -> Unit)))))
