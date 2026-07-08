#!/bin/bash

# ==========================================
# Ustawienia połączenia SCP + USUWANIE PO WERYFIKACJI
# ==========================================
SSH_HOST="twoj.adres.appliance.com" # IP lub nazwa hosta appliance
SSH_USER="user_appliance"           # Użytkownik na serwerze
REMOTE_DIR="/sciezka/do/plikow/"    # Ścieżka docelowa na serwerze (np. /data/backups/)

SSH_KEY="/home/admin/.ssh/id_ed25519" # Ścieżka do klucza SSH (ed25519)

LOG_FILE="/tmp/Sys_config_upload.log"
UPLOAD_FOLDER="./upload"

# Włącz tryb logowania do pliku i terminalu
set -euo pipefail

mkdir -p "$UPLOAD_FOLDER" 2> /dev/null || {
  echo "Nie można utworzyć folderu $UPLOAD_FOLDER"
  exit 1
}
mkdir -p "$(dirname "$LOG_FILE")"

log_msg() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

log_msg "Start procesu czyszczenia i wysyłania plików TGZ..."

# ==========================================
# FUNKCJA POMOCNICZA: Normalizacja Daty (KOREKTA SORTOWANIA)
# ==========================================
# Format inputu w nazwie: DD_Mon_YYYY_HH_MM_SS (np. 22_May_2026_10_10_04)
# Wyprowadza format porównywalny: YYYY_MM_DD_HH_MM_SS
normalize_date() {
  local raw_date="$1"

  # Definicja miesięcy w liczbach (ang.)
  declare -A months
  months=([Jan]=01 [Feb]=02 [Mar]=03 [Apr]=04 [May]=05 [Jun]=06
    [Jul]=07 [Aug]=08 [Sep]=09 [Oct]=10 [Nov]=11 [Dec]=12)

  # Parsowanie: dzielimy po podkreślniku
  local day=$(echo "$raw_date" | cut -d'_' -f1)
  local month_name=$(echo "$raw_date" | cut -d'_' -f2)
  local year=$(echo "$raw_date" | cut -d'_' -f3)
  local hour=$(echo "$raw_date" | cut -d'_' -f4)
  local min=$(echo "$raw_date" | cut -d'_' -f5)
  local sec=$(echo "$raw_date" | cut -d'_' -f6)

  # Konwersja miesiąca na liczbę
  local month_num="${months[$month_name]:-00}"

  # Zwracam string porównywalny leksykograficznie (YYYY_MM_DD...)
  echo "$year$month_num${day}${hour}${min}${sec}"
}

# ==========================================
# CZĘŚĆ 0: SPRAWDZENIE FOLDERU UPLOAD
# ==========================================

shopt -s nullglob
all_files=(*.tgz) # Filtrujemy tylko .tgz (w razie potrzeby zmień na *.tar czy *.tgz)

if [ ${#all_files[@]} -eq 0 ]; then
  log_msg "Błąd: W katalogu nie znaleziono żadnych plików .tgz"
  exit 1
fi

log_msg "Sprawdzanie zawartości folderu '$UPLOAD_FOLDER'..."

declare -a files_to_upload=()

# Jeśli folder upload NIE jest pusty, dodajemy istniejące pliki do listy wysyłki
if [ -n "$(ls -A "$UPLOAD_FOLDER" 2> /dev/null)" ]; then
  log_msg "Folder '$UPLOAD_FOLDER' zawiera pliki. Dodaję je do listy wysyłki..."

  for file in "$UPLOAD_FOLDER"/*; do
    # Sprawdzamy rozszerzenie (ustawione powyżej)
    if [[ "$(basename "$file")" == *.tgz ]]; then
      files_to_upload+=("$file")
    fi
  done

  log_msg "Znaleziono ${#files_to_upload[@]} plików w folderze upload/ - dodane do wysyłki."
else
  log_msg "Folder '$UPLOAD_FOLDER' jest pusty. Wczytujemy nowe snapshoty z katalogu bieżącego..."
fi

# ==========================================
# CZĘŚĆ 1: ANALIZA I PRZENOSZENIE STARYCH PLIKÓW
# ==========================================
declare -A best_files # Najnowsze snapshoty per system (dla plików w katalogu bieżącym)

for file in "${all_files[@]}"; do
  # Wyodrębnienie Nazwy Systemu z nowego formatu: backup_-<system>_<domain>.<date>.tgz
  # Usuwamy "backup_" i pierwszą część po hyfenie przed drugą podkreślnikową sekcją (domenę)
  # Przykład: backup_-fwpl2-_... -> system = fwpl2

  local_name="${file#*_}" # usuń pierwszy segment nazwy jeśli to było w pętli, ale tu całość
  # Prosta logika: usuwamy "backup_" na początku
  local_rest="${local_name#backup_-}"
  # System jest częścią przed kolejnym "_" (przed domena) lub przed datą.
  # Format sugeruje: backup_-SYSTEM-_DOMAIN.DOMAIN.DATE...
  # Rozbijamy po "_" i bierzemy drugą część? Nie, lepiej znaleźć segment SYSTEMU.

  # Bezpieczniejsze wyodrębnienie dla tego konkretnego formatu:
  # 1. Usuń "backup_-" (jeśli jest) lub "backup_"
  rest="${local_name#backup_-}"
  # Reszta to np: fwpl2-_fwpl2.erv-global.net_22_May_2026...

  # System znajduje się przed kolejnym underscore "_" który zaczyna sekcję domeny/dati
  system_name=$(echo "$rest" | cut -d'_' -f1) # Pierwsza część: fwpl2

  # Usunięcie ewentualnego końcowego hyfenu jeśli jest (np. fwpl2-)
  system_name="${system_name%-}"

  # Pobieranie daty/godziny dla porównania
  # Format w nazwie: _DD_Mon_YYYY_HH_MM_SS.tgz (część po drugim underscore przed rozszerzeniem)
  file_timestamp_raw=$(echo "$file" | sed 's/.*_\([0-9][0-9]*_[A-Za-z]*_[0-9]*_[0-9]*_[0-9]*\)\.tgz/\1/')

  # Normalizacja daty na liczbę (np. 2026_05_22...)
  file_timestamp=$(normalize_date "$file_timestamp_raw")

  if [ -z "${best_files[$system_name]+x}" ]; then
    best_files[$system_name]="$file"
  else
    # Porównanie daty (numerowej) w Bashu działa poprawnie leksykograficznie dla formatu YYYYMM...
    if [[ "$file_timestamp" > "${best_files[$system_name]}" ]]; then
      log_msg "Aktualizacja dla $system_name: ${best_files[$system_name]} -> $file"
      best_files[$system_name]="$file"
    fi
  fi
done

# ==========================================
# CZĘŚĆ 2: PRZENOSZENIE STARYCH PLIKÓW DO UPLOAD
# ==========================================
log_msg "Przenoszenie starszych plików do katalogu '$UPLOAD_FOLDER'..."

for file in "${all_files[@]}"; do
  system_name=$(echo "$file" | sed 's/.*_-//; s/_/\./1') # Wyciąganie nazwy system z nowego formatu

  # Ponieważ wyżej już odczytaliśmy best_files dla tego systemu, sprawdzamy czy ten plik nie jest najlepszym
  if [ -n "${best_files[$system_name]+x}" ]; then
    if [[ "$file" != "${best_files[$system_name]}" ]]; then
      log_msg "Przenoszenie starego: $file -> ./upload/"
      mv "$file" "$UPLOAD_FOLDER/" || {
        log_msg "Błąd przy przenoszeniu pliku: $file"
        exit 1
      }
    fi
  else
    log_msg "Ostrzeżenie: System $system_name nie ma zapamiętanego 'najlepszego' pliku (brak w tablicy)"
  fi
done

# ==========================================
# CZĘŚĆ 3: WYSYŁANIE I USUWANIE (KONTAKT Z LISTĄ FILES_TO_UPLOAD)
# ==========================================

if [ ${#files_to_upload[@]} -eq 0 ]; then
  log_msg "Brak plików do wysłania na serwer SSH."
else
  log_msg "Rozpoczęcie wysyłania ${#files_to_upload[@]} plików na serwer: $SSH_HOST"

  for local_file in "${files_to_upload[@]}"; do
    remote_name=$(basename "$local_file")

    log_msg "Wysyłanie: $remote_name na $SSH_HOST${REMOTE_DIR}"

    # 1. Przesyłanie pliku SCP (SRC -> DST)
    # Używamy klucza SSH i trybu batchowego
    if ! scp -i "$SSH_KEY" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=60 \
      "$local_file" \
      "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/${remote_name}" 2>&1 | tee -a "$LOG_FILE"; then
      log_msg "BŁĄD: Nie udało się wysłać pliku $remote_name!"
      exit 1
    fi

    # 2. Weryfikacja istnienia pliku na serwerze (SFTP LS)
    log_msg "Sprawdzanie, czy plik istnieje na serwerze..."

    if ! sftp -i "$SSH_KEY" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=60 \
      "${SSH_USER}@${SSH_HOST}" <<< "ls ${REMOTE_DIR}/${remote_name}" 2> /dev/null; then
      log_msg "BŁĄD: Plik $remote_name nie został zapisany na serwerze (sftp ls nie znalazł pliku)."
      exit 1
    fi

    # 3. Weryfikacja przez test -f w SSH
    if ! sftp -i "$SSH_KEY" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=60 \
      "${SSH_USER}@${SSH_HOST}" <<< "test -f ${REMOTE_DIR}/${remote_name} && echo YES || echo NO" 2> /dev/null | grep -q YES; then
      log_msg "BŁĄD: Weryfikacja przez test -f nie potwierdziła pliku $remote_name!"
      exit 1
    fi

    # ==========================================
    # CZĘŚĆ 4: USUWANIE PLIKU Z FOLDERU UPLOAD
    # ==========================================

    log_msg "Plik $remote_name wysłany i zweryfikowany na serwerze."
    log_msg "Usuwanie pliku z lokalnego folderu '$UPLOAD_FOLDER'..."

    if rm "$local_file"; then
      log_msg "Plik $remote_name usunięty z katalogu upload/"
    else
      log_msg "BŁĄD: Nie udało się usunąć pliku $remote_name z katalogu upload/"
    fi
  done

  log_msg "Operacja wysyłania, weryfikacji i czyszczenia zakończona sukcesem."

fi

log_msg "Operacja czyszczenia i transferu zakończona."
