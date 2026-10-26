# A trusted compiler's success, failure and input-request outcomes. Arguments
# after the scenario match compile MODE SOURCE OUTPUT GENERATED DIRECTORY ...
set -eu
scenario=$1
output=$4
generated=$5
case "$scenario" in
  stderr)
    printf 'generate 123\n' >&2
    exit 1 ;;
  stale)
    test ! -e "$generated/request.datum"
    printf 'completed' > "$output" ;;
  malformed)
    printf '(generate "123") ()\n' > "$generated/request.datum"
    exit 1 ;;
  success-request)
    printf '(generate "123")\n' > "$generated/request.datum" ;;
  publication-failed)
    printf '(artifact "client" "application.sld" 3 8)\n' > "$generated/request.datum"
    printf 'input publication failed\n' >&2
    exit 2 ;;
  artifact)
    printf '(artifact "client" "application.sld" 3 8)\n' > "$generated/request.datum"
    exit 1 ;;
  generated)
    printf '(generate "123")\n' > "$generated/request.datum"
    exit 1 ;;
  *) exit 2 ;;
esac
