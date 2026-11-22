;; Who made the LPC sheets a program embeds, and under which licenses,
;; read from the packs' own credit files when the program is built. A
;; credit names a part the way its pack does, with its authors and what
;; each changed, its licenses and its sources: the title, author, source
;; and license that a CC-BY credit asks for. Each pack keeps its credits in
;; a format of its own: the clothing updates in a CSV table, the hair pack
;; in a text table, the character bases in a section for each body and
;; head; wulax's sprites credit only the whole pack, as ATTRIBUTION.md
;; records. `credits-library` fails the build when an embedded sheet has
;; no credit, so what a program credits cannot fall behind what it
;; carries.
(define-library (lpc credits)
  (export
   Credit
   credits-library)
  (import
   (snail core base)
   (snail core io)
   (snail shell syntax))
  (begin

    ;; ---- Credits ----

    ;; One part of a pack, and the sheets of it a program embeds, each by
    ;; its file's name without `.png`: mostly the colors it is drawn in.
    (record Credit
      ((title String)
       (pack String)
       (authors String)
       (licenses String)
       (changes String)
       (sources (List String))
       (sheets (List String))))

    ;; The credit of the sheet at `path`, from the pack whose folder holds
    ;; it. A sheet no pack credits stops the build.
    (define (path-credit (packs Packs) (path String)) (→ Credit)
      (match (cond ((prefix? clothing-folder path)
                    (clothing-credit (● packs clothing) (after clothing-folder path)))
                   ((prefix? hair-folder path)
                    (hair-credit (● packs hair) (after hair-folder path)))
                   ((prefix? bases-folder path)
                    (base-credit (● packs bases) (after bases-folder path)))
                   ((prefix? wulax-folder path) (Some (wulax-credit (after wulax-folder path))))
                   (else (None)))
        ((Some credit) (Credit-sheets-set credit (list (file-stem path))))
        ((None) (panic (string-append "no LPC credit names " path)))))

    ;; Each part once, its sheets gathered, ordered by pack and title.
    (define (merged (credits (List Credit))) (→ (List Credit))
      (list-sort (lambda (a b) (string<? (part-name a) (part-name b)))
                 (fold-left merge-credit (Nil) credits)))

    (define (merge-credit (merged (List Credit)) (credit Credit)) (→ (List Credit))
      (if (any? (lambda (other) (string=? (part-name other) (part-name credit))) merged)
          (map (lambda (other)
                 (if (string=? (part-name other) (part-name credit))
                     (Credit-sheets-set other (delete-duplicates string=?
                                                                 (append (● other sheets)
                                                                         (● credit sheets))))
                     other))
               merged)
          (Cons credit merged)))

    (define (part-name (credit Credit)) (→ String)
      (string-append (● credit pack) " / " (● credit title)))

    ;; ---- The packs' credit files ----

    (define clothing-folder (→ String) "src/lpc/lpc-clothing-updates/spritesheets/")
    (define hair-folder (→ String) "src/lpc/lpc-hair/hair/")
    (define bases-folder (→ String) "src/lpc/lpc-character-bases-v3_1/")
    (define wulax-folder (→ String) "src/lpc/lpc_entry/")

    ;; The clothing table's rows and the hair table's, as fields, and the
    ;; lines of the bases' credits.
    (record Packs
      ((clothing (List (List String)))
       (hair (List (List String)))
       (bases (List String))))

    (define (read-packs (fs Fs)) (→ Packs)
      (new Packs
        (clothing (filter (lambda (row) (not (string=? (list-ref row 0) "")))
                          (map csv-fields
                               (list-tail
                                (file-lines fs
                                            "src/lpc/lpc-clothing-updates/CREDITS-clothing-updates.csv")
                                1))))
        (hair (map table-fields
                   (filter table-row? (file-lines fs "src/lpc/lpc-hair/CREDITS-hair.txt"))))
        (bases (file-lines fs "src/lpc/lpc-character-bases-v3_1/CREDITS.txt"))))

    (define (file-lines (fs Fs) (path String)) (→ (List String))
      (map trim-end (split (read-file fs path) #\newline)))

    ;; ---- Clothing ----

    ;; A row of the clothing table names a folder of the pack's
    ;; spritesheets, and credits what the longest such folder holds:
    ;; `legs/skirts/plain` the plain skirts, whatever the build.
    (define (clothing-credit (rows (List (List String))) (part String)) (→ (Option Credit))
      (match (fold-left (lambda (best row)
                          (if (and (holds? (list-ref row 0) part) (longer? row best))
                              (Some row)
                              best))
                        (None)
                        rows)
        ((Some row) (Some (clothing-row-credit row)))
        ((None) (None))))

    (define (holds? (folder String) (part String)) (→ Bool)
      (prefix? (string-append folder "/") part))

    (define (longer? (row (List String)) (best (Option (List String)))) (→ Bool)
      (match best
        ((Some other) (> (string-length (list-ref row 0)) (string-length (list-ref other 0))))
        ((None) #t)))

    ;; The columns are the folder, notes on how it was made, the authors,
    ;; the licenses, fifteen sources and a status.
    (define (clothing-row-credit (row (List String))) (→ Credit)
      (new Credit
        (title (list-ref row 0))
        (pack "[LPC] Clothing Updates")
        (authors (list-ref row 2))
        (licenses (list-ref row 3))
        (changes (list-ref row 1))
        (sources (filter non-empty? (take (list-drop row 4) 15)))
        (sheets (Nil))))

    ;; The fields of a CSV line: commas separate them, and a quoted field
    ;; may hold commas and doubled quotes.
    (define (csv-fields (line String)) (→ (List String))
      (let loop ((index 0) (quoted #f) (field (Nil)) (fields (Nil)))
        (if (= index (string-length line))
            (reverse (Cons (list->string (reverse field)) fields))
            (let ((char (string-ref line index)))
              (cond ((and quoted (char=? char #\") (quote-at? line (+ index 1)))
                     (loop (+ index 2) #t (Cons #\" field) fields))
                    ((char=? char #\") (loop (+ index 1) (not quoted) field fields))
                    ((and (not quoted) (char=? char #\,))
                     (loop (+ index 1) #f (Nil) (Cons (list->string (reverse field)) fields)))
                    (else (loop (+ index 1) quoted (Cons char field) fields)))))))

    (define (quote-at? (line String) (index I64)) (→ Bool)
      (and (< index (string-length line)) (char=? (string-ref line index) #\")))

    ;; ---- Hair ----

    ;; A row of the hair table names a style by its folder, sometimes with
    ;; its source's name after it: `long_messy (puck)`.
    (define (hair-credit (rows (List (List String))) (part String)) (→ (Option Credit))
      (let ((style (list-ref (split part #\/) 0)))
        (match (find (lambda (row) (string=? (list-ref (split (list-ref row 1) #\space) 0) style))
                     rows)
          ((Some row) (Some (hair-row-credit row)))
          ((None) (None)))))

    ;; The columns, between bars, are the name, the authors, the licenses,
    ;; the changes and the sources.
    (define (hair-row-credit (row (List String))) (→ Credit)
      (new Credit
        (title (list-ref row 1))
        (pack "[LPC] Hair")
        (authors (list-ref row 2))
        (licenses (list-ref row 3))
        (changes (list-ref row 4))
        (sources (filter non-empty? (split (list-ref row 5) #\space)))
        (sheets (Nil))))

    ;; A row starts with a bar; the header names its columns and a line of
    ;; dashes follows it.
    (define (table-row? (line String)) (→ Bool)
      (and (prefix? "|" line)
           (not (prefix? "|-" line))
           (not (string=? (list-ref (table-fields line) 1) "name"))))

    (define (table-fields (line String)) (→ (List String))
      (map trim (split line #\|)))

    ;; ---- Bodies and heads ----

    ;; The section of the bases' credits for each body and head the
    ;; catalog draws, by the part's folder.
    (define base-sections (→ (List (Pair String String)))
      (list (new Pair (first "bodies/male") (second "Male (adult) body"))
            (new Pair (first "bodies/female") (second "Female (adult) body"))
            (new Pair (first "bodies/teen") (second "Teen body"))
            (new Pair (first "bodies/muscular") (second "Muscular body"))
            (new Pair (first "bodies/pregnant") (second "Pregnant body"))
            (new Pair (first "heads/human_male") (second "Human male head"))
            (new Pair (first "heads/human_female") (second "Human female head"))
            (new Pair (first "heads/human_male_elderly") (second "Human male/female elderly heads"))
            (new Pair
              (first "heads/human_female_elderly")
              (second "Human male/female elderly heads"))
            (new Pair (first "heads/orc_male") (second "Orc male head"))
            (new Pair (first "heads/orc_female") (second "Orc female head"))
            (new Pair (first "heads/lizard_male") (second "Lizardman Male/Female Head"))
            (new Pair (first "heads/lizard_female") (second "Lizardman Male/Female Head"))
            (new Pair (first "heads/wolf_male") (second "Wolfman head"))
            (new Pair (first "heads/wolf_female") (second "Wolfman head"))
            (new Pair (first "heads/boarman") (second "Boarman Head"))
            (new Pair (first "heads/minotaur") (second "Minotaur Head"))))

    (define (base-credit (lines (List String)) (part String)) (→ (Option Credit))
      (match (assoc-ref base-sections (string-join (take (split part #\/) 2) "/"))
        ((Some heading) (Some (section-credit heading (section-lines lines heading))))
        ((None) (None))))

    ;; The lines under `### HEADING`, up to the next heading.
    (define (section-lines (lines (List String)) (heading String)) (→ (List String))
      (match (list-index (lambda (line) (string=? line (string-append "### " heading))) lines)
        ((Some index)
         (let loop ((rest (list-tail lines (+ index 1))) (taken (Nil)))
           (match rest
             ((Cons line more)
              (if (prefix? "#" line) (reverse taken) (loop more (Cons line taken))))
             ((Nil) (reverse taken)))))
        ((None) (panic (string-append "the LPC bases credit no " heading)))))

    ;; A section is its licenses, then `Created by:` and a list: each
    ;; author, unindented, then the works they drew it from, each with its
    ;; licenses, its address and, in parentheses, what they did.
    (define (section-credit (heading String) (lines (List String))) (→ Credit)
      (new Credit
        (title heading)
        (pack "LPC Character Bases")
        (authors (string-join (map (lambda (line) (after "- " line))
                                   (filter (lambda (line) (prefix? "- " line)) lines))
                              ", "))
        (licenses (match (find non-empty? lines) ((Some line) line) ((None) "")))
        (changes (string-join (contributions lines) "; "))
        (sources (delete-duplicates string=?
                                    (map (lambda (line) (after "- " (trim line)))
                                         (filter (lambda (line) (prefix? "- http" (trim line)))
                                                 lines))))
        (sheets (Nil))))

    ;; What each author did, as `AUTHOR: WHAT`.
    (define (contributions (lines (List String))) (→ (List String))
      (reverse
       (● (fold-left (lambda (state line)
                       (cond ((prefix? "- " line)
                              (new Pair (first (after "- " line)) (second (● state second))))
                             ((prefix? "- (" (trim line))
                              (new Pair (first (● state first))
                                   (second (Cons (string-append (● state first)
                                                                ": "
                                                                (parenthesized (trim line)))
                                                 (● state second)))))
                             (else state)))
                     (new Pair (first "") (second (Nil)))
                     lines)
          second)))

    ;; `- (WHAT)` as WHAT.
    (define (parenthesized (line String)) (→ String)
      (substring line 3 (- (string-length line) 1)))

    ;; ---- Wulax's sprites ----

    ;; The pack credits no file of its own; ATTRIBUTION.md records its
    ;; author, its licenses and its page.
    (define (wulax-credit (part String)) (→ Credit)
      (new Credit
        (title (folder part))
        (pack "[LPC] Medieval fantasy character sprites")
        (authors "Johannes Sjölund (wulax), Stephen Challener (Redshrike)")
        (licenses "CC-BY-SA 3.0, GPL 3.0, OGA-BY 3.0")
        (changes
         "Johannes Sjölund (wulax): derived from the LPC base sprites by Stephen Challener (Redshrike)")
        (sources (list "https://opengameart.org/content/lpc-medieval-fantasy-character-sprites"))
        (sheets (Nil))))

    ;; ---- Text ----

    (define (prefix? (prefix String) (text String)) (→ Bool)
      (and (<= (string-length prefix) (string-length text))
           (string=? prefix (substring text 0 (string-length prefix)))))

    (define (after (prefix String) (text String)) (→ String)
      (substring text (string-length prefix) (string-length text)))

    (define (non-empty? (text String)) (→ Bool)
      (> (string-length text) 0))

    ;; The pieces of `text` between each `separator`.
    (define (split (text String) (separator Char)) (→ (List String))
      (let loop ((index (- (string-length text) 1)) (end (string-length text)) (pieces (Nil)))
        (cond ((< index 0) (Cons (substring text 0 end) pieces))
              ((char=? (string-ref text index) separator)
               (loop (- index 1) index (Cons (substring text (+ index 1) end) pieces)))
              (else (loop (- index 1) end pieces)))))

    (define (trim-end (text String)) (→ String)
      (let loop ((end (string-length text)))
        (if (and (> end 0) (char-whitespace? (string-ref text (- end 1))))
            (loop (- end 1))
            (substring text 0 end))))

    (define (trim (text String)) (→ String)
      (let ((text (trim-end text)))
        (let loop ((start 0))
          (if (and (< start (string-length text)) (char-whitespace? (string-ref text start)))
              (loop (+ start 1))
              (substring text start (string-length text))))))

    ;; `a/b/c.png` has the folder `a/b` and the stem `c`.
    (define (folder (path String)) (→ String)
      (string-join (reverse (list-tail (reverse (split path #\/)) 1)) "/"))

    (define (file-stem (path String)) (→ String)
      (let ((name (after (string-append (folder path) "/") path)))
        (substring name 0 (- (string-length name) (string-length ".png")))))

    ;; ---- Library ----

    ;; The library `name` exporting `credits`, the credit of each part the
    ;; sheets at `paths` come from, read from the packs now.
    (define (credits-library (fs Fs) (name (List String)) (paths (List String))) (→ Syntax)
      (let ((packs (read-packs fs)))
        (library-syntax name
                        (list "credits")
                        (list (list "snail" "core" "base") (list "lpc" "credits"))
                        (list (form "define"
                                    (list (SymbolSyntax "credits")
                                          (form "→"
                                                (list (form "List" (list (SymbolSyntax "Credit")))))
                                          (form "list"
                                                (map credit-syntax
                                                     (merged
                                                      (map (lambda (path) (path-credit packs path))
                                                           paths))))))))))

    ;; `(new Credit (title "...") ... (sources (list "..." ...)) ...)`.
    (define (credit-syntax (credit Credit)) (→ Syntax)
      (form "new"
            (list (SymbolSyntax "Credit")
                  (form "title" (list (StringSyntax (● credit title))))
                  (form "pack" (list (StringSyntax (● credit pack))))
                  (form "authors" (list (StringSyntax (● credit authors))))
                  (form "licenses" (list (StringSyntax (● credit licenses))))
                  (form "changes" (list (StringSyntax (● credit changes))))
                  (form "sources" (list (strings-syntax (● credit sources))))
                  (form "sheets" (list (strings-syntax (● credit sheets)))))))

    (define (strings-syntax (texts (List String))) (→ Syntax)
      (form "list" (map (lambda (text) (StringSyntax text)) texts)))

    ))
