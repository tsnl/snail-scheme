;; Khronos's glTF sample models and sample environments, every file linked
;; and none embedded: `(sample-model "Sponza")` gives the model's glTF/
;; files as Resources, and a program reads each with `read-resource` when
;; it needs it, so the browser fetches only the files a scene uses. The
;; files are those `scripts/fetch-khronos-samples` fetched beside this
;; recipe, listed when the library is built (embed.sld).
(generate-library (khronos samples)
                  (import
                   (snail core base)
                   (khronos embed))
                  (samples-library (list "khronos" "samples")))
