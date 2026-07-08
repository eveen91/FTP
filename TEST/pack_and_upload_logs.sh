#!/bin/bash
set -euo pipefail

readonly SOURCE_DIR="/opt/CPsuite-R81.20/fw1/log"
readonly LOG_DIR="/home/fwbackup/log_upload"
export DATE_FOR_COMPRESSION="${DATE_FOR_COMPRESSION:-$(date +%Y-%m-%d)}"
readonly YEAR=$(echo "$DATE_FOR_COMPRESSION" | cut -d'-' -f1)
readonly MONTH=$(echo "$DATE_FOR_COMPRESSION" | cut -d'-' -f2)

setup_directories() {
    mkdir -p "years/${YEAR}/${MONTH}/" || {
        log_message "ERROR" "Nie można utworzyć katalogu archiwa!"
        exit 1
    }
    log_message "INFO" "Katalog docelowy: years/${YEAR}/${MONTH}/"
}

compress_logs() {
    local temp_dir="/tmp/fortinet_logs_$$"
    mkdir -p "$temp_dir" || {
        log_message "ERROR" "Nie można utworzyć katalogu tymczasowego!"
        exit 1
    }
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            cp "$file" "$temp_dir/" || {
                log_message "ERROR" "Nie można skopiować: $file"
                rm -rf "$temp_dir"
                exit 1
            }
        fi
    done < <(find "$SOURCE_DIR" -maxdepth 1 -type f \
        \( -name "*.log" -o -name "*.log_.*" \) -mtime +30 | sort)
    cd "$temp_dir" || {
        log_message "ERROR" "Nie można wejść do katalogu tymczasowego!"
        exit 1
    }
    local tarball_name="${DATE_FOR_COMPRESSION}.tar.gz"
    tar -czf "$tarball_name" --null -T - < <(find . -maxdepth 1 -type f) || {
        log_message "ERROR" "Kompresja archiwum się nie powiodła!"
        rm -rf "$temp_dir"
        exit 1
    }
    if [[ -f "$tarball_name" ]]; then
        mv "$tarball_name" "../.." || {
            log_message "ERROR" "Nie można przenieść archiwum!"
            exit 1
        }
        log_message "INFO" "Archiwum przeniesione: ${DATE_FOR_COMPRESSION}.tar.gz"
    else
        log_message "ERROR" "Plik archiwalny nie został utworzony po kompresji!"
        rm -rf "$temp_dir"
        exit 1
    fi
    rm -rf "$temp_dir" || {
        log_message "WARN" "Nie można usunąć katalogu tymczasowego: $temp_dir"
    }
}

log_message() {
    local level=$1
    local message="$2"
    local timestamp=$(date '+%F %T')
    printf "[%s] [%s] %s\n" "$timestamp" "$level" "$message" >&2
}

main() {
    log_message "INFO" "=== START PROCESU ARCHIWIZACJI ==="
    log_message "INFO" "Zarządzanie plikami starszymi niż 30 dni w: ${SOURCE_DIR}"

    mkdir -p "${LOG_DIR}/${YEAR:-2026}"/"${MONTH:-07}/" || {
        log_message "ERROR" "Nie można utworzyć katalogu logów!"
        exit 1
    }
    
    setup_directories
    
    mapfile -t TEMP_FILES < <(find "$SOURCE_DIR" -maxdepth 1 -type f \
        \( -name "*.log" -o -name "*.log_.*" \) -mtime +30 | sort)

    local count=${#TEMP_FILES[@]}
    log_message "INFO" "Znaleziono ${count} plików do archiwizacji"
    
    if [[ ${#TEMP_FILES[@]} -eq 0 ]]; then
        log_message "WARN" "Brak plików starszych niż 30 dni!"
        log_message "INFO" "=== PROCES ZAKOŃCZONY (brak plików do archiwizacji) ==="
        exit 0
    fi
    
    compress_logs
    
    log_message "INFO" "=== PROCES ARCHIWIZACJI UKOŃCZONE ==="
    
    # Generate log file with date in filename
    local log_file="${LOG_DIR}/${YEAR:-2026}/${MONTH:-07}/log_${DATE_FOR_COMPRESSION}.txt"
    mkdir -p "$(dirname "$log_file")" || {
        log_message "ERROR" "Nie można utworzyć katalogu do pliku logu!"
        exit 1
    }
    
    # Append logs to file
    log_message "INFO" "=== GENEROWANIE LOGU WYKONANIA ==="
    log_message "INFO" "Plik: $log_file"
    log_message "INFO" "Struktura katalogów docelowych:"
    tree -h years/${YEAR:-2026}/${MONTH:-07}/ 2>/dev/null || {
        # Fallback if 'tree' not installed
        find years/${YEAR:-2026}/${MONTH:-07}/ -type f -exec ls -lh {} \; 2>/dev/null || true
    }
    log_message "INFO" "=== LISTA PLIKÓW W ARCHIWUM ==="
    if [[ -f "years/${YEAR:-2026}/${MONTH:-07}/${DATE_FOR_COMPRESSION}.tar.gz" ]]; then
        tar -tzf "years/${YEAR:-2026}/${MONTH:-07}/${DATE_FOR_COMPRESSION}.tar.gz" | \
            awk '{print "* " $0}' || {
                log_message "WARN" "Nie można wylistować zawartość archiwum!"
            }
    fi
    log_message "INFO" "=== LISTA PLIKÓW ZARZĄDZANYCH ==="
    for file in "${TEMP_FILES[@]}"; do
        printf "  %s\n" "$file" >> "$log_file"
    done
    log_message "INFO" "=== STATYKA UPLOADU (przykładowa) ==="
    log_message "INFO" "Plik archiwalny: years/${YEAR:-2026}/${MONTH:-07}/${DATE_FOR_COMPRESSION}.tar.gz"
    log_message "INFO" "Status: SUCCESS - Archiwum utworzone pomyślnie!"
    
    # Here you can add upload logic with status logging:
    # e.g., rsync or scp to remote destination
}

main