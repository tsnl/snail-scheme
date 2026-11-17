;; The page's WebGPU device, as host/browser/gpu.mjs provides it: objects
;; are I32 ids the program chooses, and the descriptor of an object being
;; made crosses as staged Bytes of words and texts, the call's last
;; argument ((snail shell gpu)'s `fields-bytes`). A render pass is built by
;; calls: a view and its color or depth attachment, a call each, then
;; `begin-pass`. A submit queues each command buffer, then submits. Requesting the device, reading a
;; buffer and decoding an image are host operations a task waits for by
;; ticket. A string answer crosses a scalar at a time: the call answers
;; how many, and `reply-scalar` reads each. (snail shell gpu page)
;; implements the `gpu` effect over these.
(define-library (snail runtime browser gpu)
  (export
   start-device
   finish-device
   device-format
   device-features
   reply-scalar
   create
   destroy
   release
   write-buffer
   write-texture
   start-read
   finish-read
   read-byte
   start-decode
   finish-decode
   decoded-height
   keep-decoded
   drop-decoded
   encoder
   copy-buffer
   copy-texture-to-buffer
   copy-texture
   pass-view
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
   finish
   queue-buffer
   submit
   current-texture
   current-height)
  (import
   (snail core base))
  (begin
    (extern start-device "snail.runtime.browser.gpu" "start-device" (Fn I64 → Unit))
    (extern finish-device "snail.runtime.browser.gpu" "finish-device" (Fn I64 → I32))
    (extern device-format "snail.runtime.browser.gpu" "device-format" (Fn → I32))
    (extern device-features "snail.runtime.browser.gpu" "device-features" (Fn → I32))
    (extern reply-scalar "snail.runtime.browser.gpu" "reply-scalar" (Fn I32 → I32))
    (extern create "snail.runtime.browser.gpu" "create" (Fn I32 I32 Bytes → Unit))
    (extern destroy "snail.runtime.browser.gpu" "destroy" (Fn I32 → Unit))
    (extern release "snail.runtime.browser.gpu" "release" (Fn I32 → Unit))
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
    (extern keep-decoded "snail.runtime.browser.gpu" "keep-decoded" (Fn I32 → Unit))
    (extern drop-decoded "snail.runtime.browser.gpu" "drop-decoded" (Fn → Unit))
    (extern encoder "snail.runtime.browser.gpu" "encoder" (Fn I32 → Unit))
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
    (extern pass-view "snail.runtime.browser.gpu" "pass-view" (Fn I32 I32 I32 I32 I32 I32 → Unit))
    (extern pass-color "snail.runtime.browser.gpu" "pass-color" (Fn I32 F64 F64 F64 F64 I32 → Unit))
    (extern pass-depth "snail.runtime.browser.gpu" "pass-depth" (Fn I32 F64 I32 → Unit))
    (extern begin-pass "snail.runtime.browser.gpu" "begin-pass" (Fn I32 I32 → Unit))
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
    (extern finish "snail.runtime.browser.gpu" "finish" (Fn I32 I32 → Unit))
    (extern queue-buffer "snail.runtime.browser.gpu" "queue-buffer" (Fn I32 → Unit))
    (extern submit "snail.runtime.browser.gpu" "submit" (Fn → Unit))
    (extern current-texture "snail.runtime.browser.gpu" "current-texture" (Fn I32 → I32))
    (extern current-height "snail.runtime.browser.gpu" "current-height" (Fn → I32))))
