;; WebGPU through the `gpu` effect on Node, whose device is Dawn's
;; (host/native/gpu.mjs): the checks that need only a device, as the page
;; runs them ((gpu-test device)), under the handler a program on Node
;; installs itself. tests/gpu.mjs checks what it prints.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu host)
 (gpu-test device))

(provide-gpu (lambda ()
               (let ((info (request-device)))
                 (write-line (string-append "format: " (texture-format-name (● info format))))
                 (device-checks)
                 (work-done))))
