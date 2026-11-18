;; WebGPU through the `gpu` effect on Node, whose device is Dawn's
;; (host/native/gpu.mjs): the checks that need only a device, as the page
;; runs them ((gpu-test device)), then the training checks, which only a
;; real GPU runs reliably (#856), under the handler a program on Node
;; installs itself. tests/gpu.mjs checks what it prints.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (gpu-test device))

(provide-gpu (lambda ()
               (let ((info (request-device)))
                 (write-line (string-append "format: " (texture-format-name (● info format))))
                 (device-checks)
                 (training-checks)
                 (work-done))))
