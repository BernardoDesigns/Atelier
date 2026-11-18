# Shared backup naming for setup.sh and guardrails/install.sh. Source it, don't run it.
# bash 3.2 and BSD userland safe: no GNU date flags, no associative arrays.
#
# A backup is named <file>.bak.YYYYmmdd-HHMMSS-<label>. The timestamp keeps the
# names sortable and the .bak. prefix keeps the documented undo commands working.
# The label says which step made it. Nothing here ever overwrites an existing
# file: if the name is taken, -2, -3 ... is appended until it is free.
#
#   atelier_backup_path <source> <label>   prints a name that does not exist yet
#                                          (and, for a plain file, reserves it)
#   atelier_backup_log <source> <backup>   appends to $ATELIER_BACKUP_LOG when
#                                          set (setup.sh uses it to report the
#                                          pre-run original); a no-op otherwise
#
# ATELIER_BACKUP_TS overrides the timestamp (tests freeze it).

atelier_backup_path() {
    local src=$1 label=$2 ts base cand n=1
    ts=${ATELIER_BACKUP_TS:-$(date +%Y%m%d-%H%M%S)}
    base="$src.bak.$ts-$label"
    cand=$base
    while :; do
        if [ ! -e "$cand" ] && [ ! -L "$cand" ]; then
            # Plain files: claim the name atomically (noclobber) so a parallel
            # run can't take it. Folders are only checked, since a placeholder
            # file would make mv nest the folder inside or fail.
            if [ -d "$src" ] && [ ! -L "$src" ]; then
                break
            fi
            if ( set -C; : > "$cand" ) 2>/dev/null; then
                break
            fi
        fi
        n=$((n + 1))
        # Can't reserve any name (read-only folder, say): give up, don't spin.
        [ "$n" -le 1000 ] || return 1
        cand="$base-$n"
    done
    printf '%s\n' "$cand"
}

# atelier_backup_copy <source> <label>
#   Copies a file to a fresh backup name and checks the copy is byte-identical.
#   Prints the backup path and returns 0 only then. On any failure it prints why
#   to stderr, removes the empty placeholder it reserved (only if still 0 bytes)
#   and returns 1. Callers must not touch the source after a non-zero return.
atelier_backup_copy() {
    local src=$1 label=$2 dest
    if ! dest=$(atelier_backup_path "$src" "$label") || [ -z "$dest" ]; then
        echo "Could not reserve a backup name for $src, left it untouched." >&2
        return 1
    fi
    if cp "$src" "$dest" 2>/dev/null && cmp -s "$src" "$dest"; then
        atelier_backup_log "$src" "$dest"
        printf '%s\n' "$dest"
        return 0
    fi
    if [ -f "$dest" ] && [ ! -s "$dest" ]; then
        rm -f "$dest"
        echo "Backup of $src failed, so $src was left untouched (removed the empty placeholder $dest)." >&2
    else
        echo "Backup of $src failed or did not match, so $src was left untouched. Do not trust $dest." >&2
    fi
    return 1
}

# atelier_backup_move <source> <label>
#   Moves a file or folder aside to a fresh backup name. Prints the new path and
#   returns 0 on success; on failure cleans up an empty placeholder, says so on
#   stderr and returns 1, leaving the original in place.
atelier_backup_move() {
    local src=$1 label=$2 dest
    if ! dest=$(atelier_backup_path "$src" "$label") || [ -z "$dest" ]; then
        echo "Could not reserve a backup name for $src, left it in place." >&2
        return 1
    fi
    if mv "$src" "$dest" 2>/dev/null; then
        atelier_backup_log "$src" "$dest"
        printf '%s\n' "$dest"
        return 0
    fi
    if [ -f "$dest" ] && [ ! -s "$dest" ] && [ -e "$src" ]; then
        rm -f "$dest"
    fi
    echo "Could not move $src aside, so it was left in place." >&2
    return 1
}

atelier_backup_log() {
    [ -n "${ATELIER_BACKUP_LOG:-}" ] || return 0
    printf '%s\t%s\n' "$1" "$2" >> "$ATELIER_BACKUP_LOG" 2>/dev/null || true
}
