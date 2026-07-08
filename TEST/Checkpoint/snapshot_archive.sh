#!/usr/bin/env bash
#
# find_latest_snapshots.sh
#
# Analizuje pliki snapshotów o nazwach w formacie:
#   <system>_<YYYY>_<MM>_<DD>__<HH>_<MM>.tar
# np. fwpl1_2026_04_20__02_00.tar
#     rz2fwg2_2026_05_20__07_00.tar
#
# Dla każdego "systemu" (część nazwy przed znacznikiem czasu) wypisuje:
#   - najnowszy plik (do zachowania)
#   - pozostałe pliki (kandydaci do przeniesienia)
#
# Na tym etapie skrypt TYLKO WYPISUJE wynik, niczego nie przenosi ani nie kasuje.
#
# Użycie:
#   ./find_latest_snapshots.sh [katalog]
# Jeśli katalog nie podany, używany jest bieżący katalog.

set -euo pipefail

DIR="${1:-.}"

# Regex wyłuskujący system i timestamp z nazwy pliku.
# Timestamp ma stały, rozpoznawalny format: _YYYY_MM_DD__HH_MM.tar
# System to wszystko przed nim (może zawierać cyfry i litery).
REGEX='^(.+)_([0-9]{4}_[0-9]{2}_[0-9]{2}__[0-9]{2}_[0-9]{2})\.tar$'

declare -A latest_file # system -> najnowsza nazwa pliku
declare -A latest_ts   # system -> najnowszy timestamp (jako string, porównywalny leksykograficznie)
declare -A all_files   # system -> lista wszystkich plików (rozdzielona '\n')

shopt -s nullglob
files=("$DIR"/*.tar)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
  echo "Brak plików .tar w katalogu: $DIR" >&2
  exit 1
fi

for filepath in "${files[@]}"; do
  fname="$(basename "$filepath")"

  if [[ "$fname" =~ $REGEX ]]; then
    system="${BASH_REMATCH[1]}"
    ts="${BASH_REMATCH[2]}"
  else
    echo "UWAGA: pomijam plik o nierozpoznanym formacie nazwy: $fname" >&2
    continue
  fi

  # dopisz do listy wszystkich plików danego systemu
  all_files["$system"]+="${fname}"$'\n'

  # sprawdź, czy to najnowszy jak dotąd timestamp dla tego systemu
  # (timestampy w formacie YYYY_MM_DD__HH_MM sortują się poprawnie leksykograficznie)
  if [[ -z "${latest_ts[$system]+x}" || "$ts" > "${latest_ts[$system]}" ]]; then
    latest_ts["$system"]="$ts"
    latest_file["$system"]="$fname"
  fi
done

echo "=== Podsumowanie per system ==="
echo

for system in "${!all_files[@]}"; do
  echo "System: $system"
  echo "  Najnowszy (do zachowania): ${latest_file[$system]}"
  echo "  Pozostałe (do przeniesienia):"

  found_others=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "$f" != "${latest_file[$system]}" ]; then
      echo "    - $f"
      found_others=1
    fi
  done <<< "${all_files[$system]}"

  if [ "$found_others" -eq 0 ]; then
    echo "    (brak, jest tylko jeden plik dla tego systemu)"
  fi
  echo
done
