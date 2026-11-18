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
        cand="$base-$n"
    done
    printf '%s\n' "$cand"
}

atelier_backup_log() {
    [ -n "${ATELIER_BACKUP_LOG:-}" ] || return 0
    printf '%s\t%s\n' "$1" "$2" >> "$ATELIER_BACKUP_LOG" 2>/dev/null || true
}
