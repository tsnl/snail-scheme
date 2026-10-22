;; Hearsay's prototypes in the browser: a menu that opens the rumor mill or
;; the favor ledger. See prototypes.md for their rules.
(import
 (lofi base)
 (lofi app)
 (hearsay shell))

(define-application Shell new-shell update-shell view-shell shell-hud shell-save shell-restore)
