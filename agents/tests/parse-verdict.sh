#!/usr/bin/env bash
# Reference implementation of the verdict grammar in commands/wrap.md.
# This is a test aid that mirrors the prose. It is not the command itself.
#
# Input: one verdict line, as the first argument or on stdin.
# Output: one action per line, in the order given:
#   F<n> fix | F<n> disagree | F<n> later | A<n> right | A<n> wrong
# Exit 1 with one message on stderr when the line is unparseable. Nothing is
# printed to stdout in that case.

if [ "$#" -ge 1 ]; then
  line=$1
else
  IFS= read -r line
fi

trim() {
  local s=$1
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

line=$(trim "$line")
if [ -z "$line" ]; then
  echo "unparseable: empty line" >&2
  exit 1
fi
case "$line" in
  *,) echo "unparseable: trailing comma" >&2; exit 1 ;;
esac

out=""
seen=","
IFS=',' read -ra toks <<< "$line"
for raw in "${toks[@]}"; do
  tok=$(trim "$raw")
  id=""
  if [[ $tok =~ ^([0-9]+)[[:space:]]+(fix|disagree|later)$ ]]; then
    id="F${BASH_REMATCH[1]}"
    word="${BASH_REMATCH[2]}"
  elif [[ $tok =~ ^A([0-9]+)[[:space:]]+(right|wrong)$ ]]; then
    id="A${BASH_REMATCH[1]}"
    word="${BASH_REMATCH[2]}"
  else
    echo "unparseable token: '$tok'" >&2
    exit 1
  fi
  case "$seen" in
    *",$id,"*) echo "unparseable: repeated id $id" >&2; exit 1 ;;
  esac
  seen="$seen$id,"
  out="$out$id $word"$'\n'
done

printf '%s' "$out"
