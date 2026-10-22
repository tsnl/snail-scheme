;; Hearsay's prototypes in the browser: a menu that opens the rumor mill or
;; the favor ledger. See prototypes.md for their rules. The cast's LPC
;; sheets are embedded through (hearsay art); see lib/lpc/ATTRIBUTION.md.
(import
 (lofi base)
 (lofi app)
 (hearsay shell)
 (hearsay art))

(: view (-> Shell Frame))
(define (view shell)
  (view-shell shell art))

(define-application Shell new-shell update-shell view shell-hud shell-save shell-restore)
