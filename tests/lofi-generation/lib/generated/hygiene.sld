(generate-library (generated hygiene)
                  (import (scheme base) (only (producer make) produce))
                  (let ((result (produce))) result))
