# A trusted compiler's success, failure and input-request outcomes. Arguments
# after the scenario match compile MODE TARGET SOURCE OUTPUT GENERATED DIRECTORY ...
set -eu
scenario=$1
output=$5
generated=$6
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
    printf '(generate "123")\n' > "$generated/request.datum"
    printf 'input publication failed\n' >&2
    exit 2 ;;
  generated)
    printf '(generate "123")\n' > "$generated/request.datum"
    exit 1 ;;
  *) exit 2 ;;
esac
