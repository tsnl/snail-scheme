;; The host's WebGPU device, as host/browser/gpu.mjs provides it on the
;; page and, over Dawn, on Node (host/native/gpu.mjs): each object is an
;; I32 id the host gives it when it makes it. The descriptor of an object
;; being made crosses as staged Bytes of words and texts, the call's last
;; argument ((snail shell gpu)'s `fields-bytes`). A render pass is built by
;; calls, an attachment each and then its timestamp writes, if any, before
;; `begin-pass`; a compute pass's timestamp writes come before
;; `begin-compute` the same way. A submit queues each command buffer, then
;; submits, and then lets go of each object destroyed since the last
;; submit. The host lets an encoder, a pass and a command buffer go once
;; used, and the canvas's texture and its views at the next
;; `current-texture`. Requesting the device, reading a buffer and decoding
;; an image are host operations a task waits for by ticket. A string answer
;; crosses a scalar at a time: the call answers how many, and
;; `reply-scalar` reads each. (snail shell gpu) implements the `gpu` effect
;; over these.
(define-library (snail runtime gpu)
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
   pass-no-color
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
   pass-timestamps
   resolve-queries
   set-compute-pipeline
   set-compute-bind-group
   dispatch
   dispatch-indirect
   end-compute
   finish
   queue-buffer
   submit
   start-done
   finish-done
   current-texture
   current-width
   current-height)
  (import
   (snail core base))
  (begin
    (extern start-device "snail.runtime.gpu" "start-device" (Fn I64 → Unit))
    (extern finish-device "snail.runtime.gpu" "finish-device" (Fn I64 → I32))
    (extern device-format "snail.runtime.gpu" "device-format" (Fn → I32))
    (extern device-features "snail.runtime.gpu" "device-features" (Fn → I32))
    (extern reply-scalar "snail.runtime.gpu" "reply-scalar" (Fn I32 → I32))
    (extern create "snail.runtime.gpu" "create" (Fn I32 Bytes → I32))
    (extern create-view "snail.runtime.gpu" "create-view" (Fn I32 Bytes → I32))
    (extern destroy "snail.runtime.gpu" "destroy" (Fn I32 → Unit))
    (extern write-buffer "snail.runtime.gpu" "write-buffer" (Fn I32 I32 Bytes → Unit))
    (extern write-texture
            "snail.runtime.gpu"
            "write-texture"
            (Fn I32 I32 I32 I32 I32 I32 I32 I32 Bytes → Unit))
    (extern start-read "snail.runtime.gpu" "start-read" (Fn I64 I32 I32 I32 → Unit))
    (extern finish-read "snail.runtime.gpu" "finish-read" (Fn I64 → I32))
    (extern read-byte "snail.runtime.gpu" "read-byte" (Fn I32 → U8))
    (extern start-decode "snail.runtime.gpu" "start-decode" (Fn I64 I32 Bytes → Unit))
    (extern finish-decode "snail.runtime.gpu" "finish-decode" (Fn I64 → I32))
    (extern decoded-height "snail.runtime.gpu" "decoded-height" (Fn → I32))
    (extern keep-decoded "snail.runtime.gpu" "keep-decoded" (Fn → I32))
    (extern encoder "snail.runtime.gpu" "encoder" (Fn → I32))
    (extern copy-buffer
            "snail.runtime.gpu"
            "copy-buffer"
            (Fn I32 I32 I32 I32 I32 I32 → Unit))
    (extern copy-texture-to-buffer
            "snail.runtime.gpu"
            "copy-texture-to-buffer"
            (Fn I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 → Unit))
    (extern copy-texture
            "snail.runtime.gpu"
            "copy-texture"
            (Fn I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 I32 → Unit))
    (extern pass-color
            "snail.runtime.gpu"
            "pass-color"
            (Fn I32 I32 F64 F64 F64 F64 I32 → Unit))
    (extern pass-no-color "snail.runtime.gpu" "pass-no-color" (Fn → Unit))
    (extern pass-depth "snail.runtime.gpu" "pass-depth" (Fn I32 I32 F64 I32 → Unit))
    (extern begin-pass "snail.runtime.gpu" "begin-pass" (Fn I32 → I32))
    (extern set-pipeline "snail.runtime.gpu" "set-pipeline" (Fn I32 I32 → Unit))
    (extern set-bind-group "snail.runtime.gpu" "set-bind-group" (Fn I32 I32 I32 → Unit))
    (extern set-vertex-buffer
            "snail.runtime.gpu"
            "set-vertex-buffer"
            (Fn I32 I32 I32 I32 → Unit))
    (extern set-index-buffer
            "snail.runtime.gpu"
            "set-index-buffer"
            (Fn I32 I32 I32 I32 → Unit))
    (extern set-scissor "snail.runtime.gpu" "set-scissor" (Fn I32 I32 I32 I32 I32 → Unit))
    (extern draw "snail.runtime.gpu" "draw" (Fn I32 I32 I32 I32 I32 → Unit))
    (extern draw-indexed
            "snail.runtime.gpu"
            "draw-indexed"
            (Fn I32 I32 I32 I32 I32 I32 → Unit))
    (extern draw-indexed-indirect
            "snail.runtime.gpu"
            "draw-indexed-indirect"
            (Fn I32 I32 I32 → Unit))
    (extern end-pass "snail.runtime.gpu" "end-pass" (Fn I32 → Unit))
    (extern begin-compute "snail.runtime.gpu" "begin-compute" (Fn I32 → I32))
    ;; The next pass's timestamp writes: the query set, and the queries
    ;; written as it begins and as it ends.
    (extern pass-timestamps "snail.runtime.gpu" "pass-timestamps" (Fn I32 I32 I32 → Unit))
    ;; An encoder's copy of `count` queries from `first` into a buffer at
    ;; an offset, eight bytes each.
    (extern resolve-queries
            "snail.runtime.gpu"
            "resolve-queries"
            (Fn I32 I32 I32 I32 I32 I32 → Unit))
    (extern set-compute-pipeline
            "snail.runtime.gpu"
            "set-compute-pipeline"
            (Fn I32 I32 → Unit))
    (extern set-compute-bind-group
            "snail.runtime.gpu"
            "set-compute-bind-group"
            (Fn I32 I32 I32 → Unit))
    (extern dispatch "snail.runtime.gpu" "dispatch" (Fn I32 I32 I32 I32 → Unit))
    (extern dispatch-indirect
            "snail.runtime.gpu"
            "dispatch-indirect"
            (Fn I32 I32 I32 → Unit))
    (extern end-compute "snail.runtime.gpu" "end-compute" (Fn I32 → Unit))
    (extern finish "snail.runtime.gpu" "finish" (Fn I32 → I32))
    (extern queue-buffer "snail.runtime.gpu" "queue-buffer" (Fn I32 → Unit))
    (extern submit "snail.runtime.gpu" "submit" (Fn → Unit))
    (extern start-done "snail.runtime.gpu" "start-done" (Fn I64 → Unit))
    (extern finish-done "snail.runtime.gpu" "finish-done" (Fn I64 → I32))
    (extern current-texture "snail.runtime.gpu" "current-texture" (Fn → I32))
    (extern current-width "snail.runtime.gpu" "current-width" (Fn → I32))
    (extern current-height "snail.runtime.gpu" "current-height" (Fn → I32))))
