(import
 (lofi base))

(effect Choice
  ((choose ctl (-> I64)))
  (host "test" ((choose "choose"))))
