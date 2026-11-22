;; The files a page's user chose, as host/browser/files.mjs keeps them: a
;; picker opens without waiting, and the latest choice, dropped or
;; picked, is listed as one string read a scalar at a time. (snail shell files page) makes its
;; `FilePicker` over these.
(define-library (snail runtime browser files)
  (export
   open-picker
   listing
   reply-scalar)
  (import
   (snail core base))
  (begin
    (extern open-picker "snail.runtime.browser.files" "open-picker" (Fn I32 → Unit))
    (extern listing "snail.runtime.browser.files" "listing" (Fn → I32))
    (extern reply-scalar "snail.runtime.browser.files" "reply-scalar" (Fn I32 → I32))))
