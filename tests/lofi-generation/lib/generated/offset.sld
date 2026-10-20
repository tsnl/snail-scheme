(generate-library (generated offset)
                  (import
                   (producer make)
                   (producer services))
                  (constant-library "(generated offset)" (read-offset)))
