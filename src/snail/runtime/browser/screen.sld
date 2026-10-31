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
    (extern frame-begin "snail.runtime.browser.screen" "frame-begin" (-> I32 F32 Unit))
    (extern camera
            "snail.runtime.browser.screen"
            "camera"
            (-> F32 F32 F32 F32 F32 F32 I32 F32 Unit))
    (extern light "snail.runtime.browser.screen" "light" (-> F32 F32 F32 F32 F32 Unit))
    (extern picture-begin "snail.runtime.browser.screen" "picture-begin" (-> I32 I32 I32 I32 Bool))
    (extern layer "snail.runtime.browser.screen" "layer" (-> I32 I32 I32 I32 I32 I32 I32 Bool))
    (extern source-begin "snail.runtime.browser.screen" "source-begin" (-> I32 I32 Unit))
    (extern source-word "snail.runtime.browser.screen" "source-word" (-> I32 Unit))
    (extern swap "snail.runtime.browser.screen" "swap" (-> I32 I32 Unit))
    (extern picture-end "snail.runtime.browser.screen" "picture-end" (-> Unit))
    (extern batch-begin
            "snail.runtime.browser.screen"
            "batch-begin"
            (-> I32 I32 I32 F32 F32 F32 F32 Bool))
    (extern instance
            "snail.runtime.browser.screen"
            "instance"
            (-> I32 F32 F32 F32 F32 F32 F32 F32 I32 F32 F32 F32 F32 Unit))
    (extern surface
            "snail.runtime.browser.screen"
            "surface"
            (-> F32 F32 I32 I32 I32 I32 I32 I32 I32 I32 Unit))
    (extern frame-end "snail.runtime.browser.screen" "frame-end" (-> Unit))
    (extern hud-begin "snail.runtime.browser.screen" "hud-begin" (-> Unit))
    (extern panel-begin "snail.runtime.browser.screen" "panel-begin" (-> I32 I32 I32 I32 Unit))
    (extern widget-begin
            "snail.runtime.browser.screen"
            "widget-begin"
            (-> I32 I32 I32 I32 I32 F32 Unit))
    (extern widget-image
            "snail.runtime.browser.screen"
            "widget-image"
            (-> I32 I32 I32 I32 I32 I32 Unit))
    (extern field "snail.runtime.browser.screen" "field" (-> I32 Unit))
    (extern text-character "snail.runtime.browser.screen" "text-character" (-> Char Unit))
    (extern hud-end "snail.runtime.browser.screen" "hud-end" (-> Unit))))
