(generate-library (apps last-mile lines)
                  (import
                   (snail core base)
                   (only (snail core io) Arguments Fs)
                   (only (snail shell process) Processes)
                   (only (snail shell resource) Resources)
                   (snail shell game ink))
                  (lambda ((arguments Arguments)
                           (fs Fs)
                           (processes Processes)
                           (resources Resources))
                    (ink-library arguments
                                 fs
                                 processes
                                 resources
                                 (list "apps" "last-mile" "lines")
                                 "rosa.ink")))
