(generate-library (generated answer)
                  (import
                   (producer make)
                   (generated offset))
                  (dependent-library "(generated answer)" (value)))
