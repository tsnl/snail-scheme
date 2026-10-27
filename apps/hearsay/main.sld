;; Hearsay's prototypes in the browser: a menu that opens the rumor mill or
;; the favor ledger. See prototypes.md for their rules. The cast's LPC
;; sheets are embedded through (hearsay art); see src/lpc/ATTRIBUTION.md.
(import
 (snail-core base)
 (snail-core app)
 (hearsay shell)
 (hearsay art))

(: view (-> Shell Frame))
(define (view shell)
  (view-shell shell art))

(define-application Shell
  (reset: default-reset)
  (init: new-shell)
  (update: update-shell)
  (view: view)
  (hud: shell-hud)
  (save: shell-save)
  (restore: shell-restore))
