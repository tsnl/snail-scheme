(import
 (snail core base))
(struct Entry
  ((name String (annotations (doc (string-append "not " "evaluated"))))))
