#!/bin/bash

# ==========================================
# Ustawienia połączenia SCP
# ==========================================
SSH_HOST="twoj.adres.appliance.com" # lub IP adres
SSH_USER="user_appliance"           # nazwa użytkownika na serwerze
REMOTE_DIR="/sciezka/do/plikow/"    # ścieżka docelowa na serwerze

SSH_KEY="/home/admin/.ssh/id_ed25519" # ścieżka do klucza SSH (ed25519)

LOG_FILE="/tmp/fwpl_cleanup.log"
UPLOAD_FOLDER="./upload"

# Włącz tryb logowania do pliku i terminalu
set -euo pipefail

#mkdir -p "$UPLOAD_FOLDER" 2> /dev/null || {
#  echo "Nie można utworzyć folderu $UPLOAD_FOLDER"
#  exit 1
#}
mkdir -p "$(dirname "$LOG_FILE")"

log_msg() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

log_msg "Start procesu czyszczenia i wysyłania plików SCP..."

# ==========================================
# CZĘŚĆ 1: ANALIZA I PRZENOSZENIE STARYCH PLIKÓW
# ==========================================
declare -A best_files   # Najnowsze snapshoty per system
declare -a all_files=() # Wszystkie pliki tar

shopt -s nullglob
all_files=(*.tar)

if [ ${#all_files[@]} -eq 0 ]; then
  log_msg "Błąd: W katalogu nie znaleziono żadnych plików .tar"
  exit 1
fi

log_msg "Analiza najnowszych snapshotów dla każdego systemu..."
for file in "${all_files[@]}"; do
  system_name="${file%%_*}" # np. fwpl1
  rest="${file#*_}"         # usuń system
  timestamp="${rest%.tar}"  # data i godzina

  if [ -z "${best_files[$system_name]+x}" ]; then
    best_files[$system_name]="$file"
  else
    if [[ "$timestamp" > "${best_files[$system_name]}" ]]; then
      log_msg "Aktualizacja dla $system_name: ${best_files[$system_name]} -> $file"
      best_files[$system_name]="$file"
    fi
  fi
done

# ==========================================
# CZĘŚĆ 2: PRZENOSZENIE STARYCH PLIKÓW DO UPLOAD
# ==========================================
log_msg "Przenoszenie starszych plików do katalogu '$UPLOAD_FOLDER'..."

declare -a files_to_upload=() # Lista plików do wysłania na serwer

for file in "${all_files[@]}"; do
  system_name="${file%%_*}"

  if [ -n "${best_files[$system_name]+x}" ]; then
    if [[ "$file" != "${best_files[$system_name]}" ]]; then
      log_msg "Przenoszenie starego: $file -> ./upload/"
      mv "$file" "$UPLOAD_FOLDER/" || {
        log_msg "Błąd przy przenoszeniu pliku: $file"
        exit 1
      }

      # Dodajemy do listy plików, które mają trafić na FTP
      files_to_upload+=("$UPLOAD_FOLDER/${file##*/}")
    fi
  else
    log_msg "Ostrzeżenie: System $system_name nie ma zapamiętanego 'najlepszego' pliku"
  fi
done

if [ ${#files_to_upload[@]} -eq 0 ]; then
  log_msg "Brak plików do wysłania na serwer SSH."
else
  log_msg "Rozpoczęcie wysyłania ${#files_to_upload[@]} plików na serwer: $SSH_HOST"

  # ==========================================
  # CZĘŚĆ 3: WYSYŁANIE DO SERWERA APPLIANCE (SCP + KLUCZ SSH)
  # ==========================================

  for local_file in "${files_to_upload[@]}"; do
    remote_name=$(basename "$local_file")

    log_msg "Wysyłanie: $remote_name na $SSH_HOST${REMOTE_DIR}"

    # SCP z kluczem SSH - BatchMode dla automatyzacji, StrictHostKeyChecking=no dla wygody
    if ! scp -i "$SSH_KEY" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=60 \
      "$local_file" \
      "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/${remote_name}" 2> /dev/null; then
      log_msg "Błąd wysyłania: $remote_name na serwerze SSH."
      exit 1
    fi

    log_msg "Plik $remote_name wysłany pomyślnie."
  done

  log_msg "Operacja wysyłania zakończona sukcesem."

fi

log_msg "Operacja czyszczenia i transferu zakończona."
