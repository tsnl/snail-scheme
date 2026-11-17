;; The page's WebGPU device, as host/browser/gpu.mjs provides it: each
;; object is an I32 id the host gives it when it makes it. The descriptor
;; of an object being made crosses as staged Bytes of words and texts, the
;; call's last argument ((snail shell gpu)'s `fields-bytes`). A render
;; pass is built by calls, an attachment each, then `begin-pass`; a submit
;; queues each command buffer, then submits, and then lets go of each
;; object destroyed since the last submit. The host lets an encoder, a
;; pass and a command buffer go once used, and the canvas's texture and its
;; views at the next `current-texture`. Requesting the device, reading a
;; buffer and decoding an image are host operations a task waits for by
;; ticket. A string answer crosses a scalar at a time: the call answers how
;; many, and `reply-scalar` reads each. (snail shell gpu page) implements
;; the `gpu` effect over these.
(define-library (snail runtime browser gpu)
  (export
   start-device
   finish-device
   device-format
   device-features
   reply-scalar
   create
   create-view
   destroy
   write-buffer
   write-texture
   start-read
   finish-read
   read-byte
   start-decode
   finish-decode
   decoded-height
   keep-decoded
   encoder
   copy-buffer
   copy-texture-to-buffer
   copy-texture
   pass-color
   pass-depth
   begin-pass
   set-pipeline
   set-bind-group
   set-vertex-buffer
   set-index-buffer
   set-scissor
   draw
   draw-indexed
   draw-indexed-indirect
   end-pass
   begin-compute
   set-compute-pipeline
   set-compute-bind-group
   dispatch
   dispatch-indirect
   end-compute
   finish
   queue-buffer
   submit
   current-texture
   current-width
   current-height)
  (import
   (snail core base))
  (begin
    (extern start-device "snail.runtime.browser.gpu" "start-device" (Fn I64 → Unit))
    (extern finish-device "snail.runtime.browser.gpu" "finish-device" (Fn I64 → I32))
    (extern device-format "snail.runtime.browser.gpu" "device-format" (Fn → I32))
    (extern device-features "snail.runtime.browser.gpu" "device-features" (Fn → I32))
    (extern reply-scalar "snail.runtime.browser.gpu" "reply-scalar" (Fn I32 → I32))
    (extern create "snail.runtime.browser.gpu" "create" (Fn I32 Bytes → I32))
    (extern create-view "snail.runtime.browser.gpu" "create-view" (Fn I32 Bytes → I32))
    (extern destroy "snail.runtime.browser.gpu" "destroy" (Fn I32 → Unit))
    (extern write-buffer "snail.runtime.browser.gpu" "write-buffer" (Fn I32 I32 Bytes → Unit))
    (extern write-texture
            "snail.runtime.browser.gpu"
            "write-texture"
            (Fn I32 I32 I32 I32 I32 I32 I32 I32 Bytes → Unit))
    (extern start-read "snail.runtime.browser.gpu" "start-read" (Fn I64 I32 I32 I32 → Unit))
    (extern finish-read "snail.runtime.browser.gpu" "finish-read" (Fn I64 → I32))
    (extern read-byte "snail.runtime.browser.gpu" "read-byte" (Fn I32 → U8))
    (extern start-decode "snail.runtime.browser.gpu" "start-decode" (Fn I64 I32 Bytes → Unit))
    (extern finish-decode "snail.runtime.browser.gpu" "finish-decode" (Fn I64 → I32))
    (extern decoded-height "snail.runtime.browser.gpu" "decoded-height" (Fn → I32))
    (extern keep-decoded "snail.runtime.browser.gpu" "keep-decoded" (Fn → I32))
    (extern encoder "snail.runtime.browser.gpu" "encoder" (Fn → I32))
    (extern copy-buffer
            "snail.runtime.browser.gpu"
            "copy-buffer"
            (Fn I32 I32 I32 I32 I32 I32 → Unit))
    (extern copy-texture-to-buffer
            "snail.runtime.browser.gpu"
            "copy-texture-to-buffer"
            (Fn I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 → Unit))
    (extern copy-texture
            "snail.runtime.browser.gpu"
            "copy-texture"
            (Fn I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 → Unit))
    (extern pass-color
            "snail.runtime.browser.gpu"
            "pass-color"
            (Fn I32 I32 F64 F64 F64 F64 I32 → Unit))
    (extern pass-depth "snail.runtime.browser.gpu" "pass-depth" (Fn I32 I32 F64 I32 → Unit))
    (extern begin-pass "snail.runtime.browser.gpu" "begin-pass" (Fn I32 → I32))
    (extern set-pipeline "snail.runtime.browser.gpu" "set-pipeline" (Fn I32 I32 → Unit))
    (extern set-bind-group "snail.runtime.browser.gpu" "set-bind-group" (Fn I32 I32 I32 → Unit))
    (extern set-vertex-buffer
            "snail.runtime.browser.gpu"
            "set-vertex-buffer"
            (Fn I32 I32 I32 I32 → Unit))
    (extern set-index-buffer
            "snail.runtime.browser.gpu"
            "set-index-buffer"
            (Fn I32 I32 I32 I32 → Unit))
    (extern set-scissor "snail.runtime.browser.gpu" "set-scissor" (Fn I32 I32 I32 I32 I32 → Unit))
    (extern draw "snail.runtime.browser.gpu" "draw" (Fn I32 I32 I32 I32 I32 → Unit))
    (extern draw-indexed
            "snail.runtime.browser.gpu"
            "draw-indexed"
            (Fn I32 I32 I32 I32 I32 I32 → Unit))
    (extern draw-indexed-indirect
            "snail.runtime.browser.gpu"
            "draw-indexed-indirect"
            (Fn I32 I32 I32 → Unit))
    (extern end-pass "snail.runtime.browser.gpu" "end-pass" (Fn I32 → Unit))
    (extern begin-compute "snail.runtime.browser.gpu" "begin-compute" (Fn I32 → I32))
    (extern set-compute-pipeline
            "snail.runtime.browser.gpu"
            "set-compute-pipeline"
            (Fn I32 I32 → Unit))
    (extern set-compute-bind-group
            "snail.runtime.browser.gpu"
            "set-compute-bind-group"
            (Fn I32 I32 I32 → Unit))
    (extern dispatch "snail.runtime.browser.gpu" "dispatch" (Fn I32 I32 I32 I32 → Unit))
    (extern dispatch-indirect
            "snail.runtime.browser.gpu"
            "dispatch-indirect"
            (Fn I32 I32 I32 → Unit))
    (extern end-compute "snail.runtime.browser.gpu" "end-compute" (Fn I32 → Unit))
    (extern finish "snail.runtime.browser.gpu" "finish" (Fn I32 → I32))
    (extern queue-buffer "snail.runtime.browser.gpu" "queue-buffer" (Fn I32 → Unit))
    (extern submit "snail.runtime.browser.gpu" "submit" (Fn → Unit))
    (extern current-texture "snail.runtime.browser.gpu" "current-texture" (Fn → I32))
    (extern current-width "snail.runtime.browser.gpu" "current-width" (Fn → I32))
    (extern current-height "snail.runtime.browser.gpu" "current-height" (Fn → I32))))
