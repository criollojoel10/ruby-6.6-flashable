#!/data/data/com.termux/files/usr/bin/bash
# Espera a que terminen uno o más runs de GitHub Actions, tolerando cortes de red.
# Uso: watch-runs.sh <repo> <run_id> [run_id...]
repo=$1; shift
declare -A state
for r in "$@"; do state[$r]=pending; done

while :; do
  pending=0
  for r in "$@"; do
    [ "${state[$r]}" = "completed" ] && continue
    out=$(gh api "repos/$repo/actions/runs/$r" --jq '.status + " " + (.conclusion // "-")' 2>/dev/null) || out=""
    if [ -n "$out" ]; then
      set -- $out
      if [ "$1" = "completed" ]; then
        state[$r]="completed"
        printf '%s\t%s\t%s\n' "$(date -u +%H:%M:%S)" "$r" "$2"
      else
        pending=1
      fi
    else
      pending=1
      printf '%s\t%s\t%s\n' "$(date -u +%H:%M:%S)" "$r" "net-error-retry"
    fi
  done
  [ "$pending" -eq 0 ] && break
  sleep 90
done
echo "TODOS TERMINADOS"
