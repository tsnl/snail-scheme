# Usage: awk -v limit=100 -f scripts/check-line-length.awk FILE ...
length($0) > limit {
    printf "%s:%d: line exceeds %d columns (%d)\n", FILENAME, FNR, limit, length($0)
    failed = 1
}
END { exit failed }
