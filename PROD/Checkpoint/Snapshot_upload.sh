#!/bin/bash

# Skrypt: cleanup_and_move.sh
# Funkcja: Znajduje najnowsze snapshoty i przenosi resztę do katalogu 'upload'
# Uwaga: Operacja jest trwała. Upewnij się, że folder 'upload' nie zawiera ważnych danych!

set -euo pipefail # Bezpieczne wyłączenie błędów

echo "Przygotowanie do czyszczenia..."

# Tworzenie katalogu docelowego jeśli go nie ma
mkdir -p upload

declare -A best_files # Klucz: system, Wartość: ścieżka pliku najnowszego snapshotu
declare -a all_files  # Lista wszystkich plików .tar do sprawdzenia

shopt -s nullglob # Unikanie błędu, jeśli nie ma plików .tar

# 1. Pobranie listy plików
all_files=(*.tar)

if [ ${#all_files[@]} -eq 0 ]; then
  echo "Błąd: W katalogu nie znaleziono żadnych plików .tar"
  exit 1
fi

echo "Analiza najnowszych plików dla każdego systemu..."
echo "================================================="

for file in "${all_files[@]}"; do
  # Wyodrębnienie nazwy Systemu (wszystko przed pierwszym podkreślnikiem)
  system_name="${file%%_*}"

  # Wyodrębnienie daty/godziny: usuwamy system, _ i .tar
  # Przykład: fwpl1_2026_04_20__02_00.tar -> 2026_04_20__02_00
  file_timestamp="${file#*_}"
  file_timestamp="${file_timestamp%.tar}"

  if [ -z "${best_files[$system_name]+x}" ]; then
    # Pierwszy raz widzimy ten system, zapisujemy plik jako "aktualny"
    best_files[$system_name]="$file"
  else
    # Sprawdzamy czy obecny plik jest nowszy od zapamiętanego
    if [[ "$file_timestamp" > "${best_files[$system_name]}" ]]; then
      echo "Nowy plik dla $system_name: ${file_timestamp}"
      best_files[$system_name]="$file"
    fi
  fi
done

echo ""
echo "Wykryto systemy:"
for key in "${!best_files[@]}"; do
  echo "- ${key} (najnowszy: ${best_files[$key]})"
done

echo ""
echo "Rozpoczęcie przenoszenia starszych plików..."
echo "==========================================="

# 2. Przenoszenie plików, które NIE są najnowszymi
for file in "${all_files[@]}"; do
  # Pobranie nazwy systemu z tego konkretnego pliku (do porównania)
  system_name="${file%%_*}"

  # Jeśli dla danego systemu mamy już zapamiętany "najlepszy" plik
  if [ -n "${best_files[$system_name]+x}" ]; then
    if [[ "$file" != "${best_files[$system_name]}" ]]; then
      # Plik jest stary (różny od najlepszy), więc przenosimy go
      echo "Przenoszenie starego pliku: $file -> upload/"
      mv "$file" ./upload/
    fi
  else
    echo "Błąd logiki: brak zapamiętanego najlepszego dla systemu $system_name"
  fi
done

echo ""
echo "Operacja zakończona."
echo "Nowoczesne snapshoty pozostały w bieżącym katalogu."
echo "Stare snapshoty zostały przeniesione do ./upload/"
