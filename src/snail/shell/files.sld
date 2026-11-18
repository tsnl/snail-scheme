;; Files the user hands the program, dropped on the page or chosen with
;; its pickers: each is its path within what was chosen and an address
;; the `fetch` effect reads its bytes from. The user chooses; the program
;; only asks, so a program reads no file it was not given.
;;
;; `open-picker` asks the user and returns at once. A choice, picked or
;; dropped, arrives as a FilesEvent ((snail shell app)), and a cancelled
;; picker as nothing. `chosen-files` then lists the latest choice; listing
;; it stops the addresses of the choice listed before.
(define-library (snail shell files)
  (export
   Chosen
   Choice
   SomeFiles
   Folder
   files
   open-picker
   chosen-files)
  (import
   (snail core base))
  (begin

    (record Chosen
      ((path String)
       (address String)))

    ;; A choice of files, or of a folder and every file under it.
    (enum Choice
      (SomeFiles)
      (Folder))

    (effect files
      ((open-picker (Fn Choice → Unit))
       (chosen-files (Fn → (List Chosen)))))

    ))
