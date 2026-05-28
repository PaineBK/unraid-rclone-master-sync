#!/bin/bash
# rclone Master-Sync: Unraid -> Remote Cloud
# Features: Multi-Job, Fast-List, Anti-Zombie, Discord-Stats, Bandwidth-Control, Network-Check, Cloud-Check, Smart-FTP, Smart-Docker
# Author: Unraid Community Member

# ==========================================
# ⚙️ EINSTELLUNGEN (ALLES HIER OBEN BEARBEITEN)
# ==========================================

# --- SYSTEM & DISCORD ---

# Trage hier den exakten Namen deines rclone-Docker-Containers ein (Groß-/Kleinschreibung beachten!)
DOCKER_NAME="Nacho-Rclone-Native-GUI" 

# Kopiere hier deinen Discord-Webhook-Link hinein, um Statusmeldungen zu erhalten
DISCORD_WEBHOOK="HIER_DEINEN_DISCORD_WEBHOOK_EINSETZEN"

# Der Pfad, in dem das Skript seine Logdateien speichern soll (wird automatisch erstellt)
LOG_DIR="/mnt/user/appdata/rclone/logs"


# --- LAUFTEMPO & BANDBREITEN-STEUERUNG ---

# Ab wie viel Uhr nachts soll das Skript mit voller Geschwindigkeit laufen? (Wert zwischen 0 und 23)
START_NIGHT_HOUR=1     

# Bis wie viel Uhr morgens soll die unbegrenzte Geschwindigkeit gelten? (Wert zwischen 0 und 23)
END_NIGHT_HOUR=5       

# Wie schnell darf der Upload TAGSÜBER sein? (Damit dein Internet zu Hause nicht blockiert wird)
SPEED_DAY="1M"         

# Wie schnell darf der Upload NACHTS sein? ("0" bedeutet absolut unbegrenzt)
SPEED_NIGHT="0"        


# --- EFFIZIENZ & SICHERHEITS-LIMITS ---

# Alle wie viele Sekunden soll eine Live-Statusmeldung in Discord gepostet werden? (3600 = jede Stunde)
MONITOR_INTERVAL=3600  

# Massenlöschungs-Schutz: Ab wie vielen gelöschten Dateien soll das Skript stoppen und 5 Minuten warten?
MAX_DELETE_LIMIT=50    

# TESTMODUS: Wenn "true", simuliert das Skript das Backup nur (kein Hochladen oder Löschen).
DRY_RUN=false          


# ------------------------------------------
# 🚀 DEINE BACKUP-AUFTRÄGE (SYNC-JOBS)
# ------------------------------------------

# --- JOB 1 ---
JOB1_ENABLE=true
JOB1_NAME="Master-Backup"
JOB1_SOURCE="Unraid:Quell-Ordner"                  
JOB1_DEST="dein-remote:Backup-Ordner"      
JOB1_FILTER="--include /appdata/** --include /Backup/**" 

# --- JOB 2 ---
JOB2_ENABLE=false
JOB2_NAME="Zweiter-Sync"
JOB2_SOURCE="Unraid:beispiel"
JOB2_DEST="dein-remote:beispiel"
JOB2_FILTER=""

# --- JOB 3 ---
JOB3_ENABLE=false
JOB3_NAME="Dritter-Sync"
JOB3_SOURCE=""
JOB3_DEST=""
JOB3_FILTER=""


# ==========================================
# 🛠️ SYSTEM-CODE (AB HIER NICHTS MEHR ÄNDERN)
# ==========================================

send_discord() {
    local escaped_msg=$(echo "$1" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
    curl -s -H "Content-Type: application/json" -X POST -d "{\"content\": \"$escaped_msg\"}" "$DISCORD_WEBHOOK" > /dev/null
}

INTERNET_OK=false
for i in {1..12}; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        INTERNET_OK=true
        break
    fi
    sleep 5
done

if [ "$INTERNET_OK" = false ]; then
    echo "[ERROR] Keine generelle Internetverbindung nach 60 Sekunden. Abbruch."
    exit 1
fi

if ! ping -c 1 drive.google.com >/dev/null 2>&1; then
    echo "[ERROR] Cloud-Server nicht erreichbar. Abbruch vor Start der Dienste."
    send_discord "🚨 **Backup blockiert:** Die Cloud-Server sind aktuell nicht erreichbar oder es liegt ein DNS-Fehler vor. Skript wurde sicherheitshalber abgebrochen."
    exit 1
fi

LOCK_FILE="/tmp/rclone_backup.lock"

if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE")
    if ps -p $PID > /dev/null; then
        echo "[ERROR] Backup läuft bereits mit PID $PID. Breche ab."
        exit 1
    fi
fi
echo $$ > "$LOCK_FILE"
START_TIME=$(date +%s)

mkdir -p "$LOG_DIR"
ls -1t "$LOG_DIR"/backup_*.log 2>/dev/null | tail -n +3 | xargs -r rm -f
CURRENT_LOG="$LOG_DIR/backup_$(date +%Y%m%d_%H%M%S).log"

FTP_WAS_OFF=false
if ! pgrep -x "vsftpd" >/dev/null 2>&1; then
    FTP_WAS_OFF=true
    echo "[INFO] FTP-Server ist deaktiviert. Starte vsftpd temporär..." | tee -a "$CURRENT_LOG"
    /etc/rc.d/rc.vsftpd start >/dev/null 2>&1
    sleep 3
fi

DOCKER_WAS_OFF=false
if [ "$(docker inspect -f '{{.State.Running}}' "$DOCKER_NAME" 2>/dev/null)" != "true" ]; then
    DOCKER_WAS_OFF=true
    echo "[INFO] Docker-Container war deaktiviert. Wird für das Backup gestartet..." | tee -a "$CURRENT_LOG"
fi

ensure_container_running() {
    if [ "$(docker inspect -f '{{.State.Running}}' "$DOCKER_NAME" 2>/dev/null)" != "true" ]; then
        echo "[INFO] Docker-Container $DOCKER_NAME ist offline. Starte Container..." | tee -a "$CURRENT_LOG"
        send_discord "⚙️ **Info:** Docker-Container \`$DOCKER_NAME\` war gestoppt. Starte automatisch neu..."
        docker start "$DOCKER_NAME" >/dev/null
        sleep 7 
    fi
}

hourly_monitor() {
    sleep 45 
    local last_bytes=0; local last_deletes=0; local last_transfers=0; local last_renames=0; local last_downloads=0
    
    while true; do
        ensure_container_running
        local current_hour=$(date +%H)
        local target_limit="$SPEED_DAY"
        local limit_msg="${SPEED_DAY} 🐌"
        
        if [ "$current_hour" -ge "$START_NIGHT_HOUR" ] && [ "$current_hour" -lt "$END_NIGHT_HOUR" ]; then
            target_limit="$SPEED_NIGHT"
            if [ "$SPEED_NIGHT" = "0" ]; then limit_msg="Unbegrenzt 🚀"; else limit_msg="${SPEED_NIGHT} 🚀"; fi
        fi
        
        docker exec $DOCKER_NAME rclone rc core/bwlimit set limit=$target_limit --rc-addr :5575 --rc-no-auth >/dev/null 2>/dev/null

        local stats=$(docker exec $DOCKER_NAME rclone rc core/stats --rc-addr :5575 --rc-no-auth 2>/dev/null)
        if [ $? -eq 0 ] && [ ! -z "$stats" ]; then
            local current_bytes=$(echo "$stats" | jq -r '.bytes // 0')
            local current_deletes=$(echo "$stats" | jq -r '.deletes // 0')
            local current_transfers=$(echo "$stats" | jq -r '.transfers // 0')
            local current_renames=$(echo "$stats" | jq -r '.renames // 0')
            local current_downloads=$(echo "$stats" | jq -r '.errors // 0')

            local total_gb=$(echo "$current_bytes" | awk '{printf "%.2f", $1 / 1073741824}')
            local speed_mb=$(echo "$speed_bytes" | awk '{printf "%.2f", $1 / 1048576}')
            
            local delta_bytes=$((current_bytes - last_bytes))
            local delta_gb=$(echo "$delta_bytes" | awk '{printf "%.2f", $1 / 1073741824}')
            local delta_transfers=$((current_transfers - last_transfers))
            local delta_deletes=$((current_deletes - last_deletes))
            local delta_renames=$((current_renames - last_renames))
            local delta_downloads=$((current_downloads - last_downloads))
            
            if [ "$percentage" = "null" ] || [ -z "$percentage" ]; then percentage="Unbekannt"; else percentage="${percentage}%"; fi
            
            local eta_str="Unbekannt"
            if [ "$eta_seconds" != "null" ] && [ "$eta_seconds" -gt 0 ] 2>/dev/null; then
                eta_str="$((eta_seconds / 3600))h $(((eta_seconds % 3600) / 60))m"
            fi

            local now=$(date +%s); local elapsed_sec=$((now - START_TIME))
            local elapsed_str="$((elapsed_sec / 3600))h $(((elapsed_sec % 3600) / 60))m"

            local msg="⏳ **Stündliches Backup-Update**\n"
            msg+="• ⏱️ **Bereits gelaufen:** ${elapsed_str}\n"
            msg+="• 📦 **Gesamt übertragen:** ${total_gb} GB (+${delta_gb} GB letzte Std.)\n"
            msg+="• 📤 **Uploads:** +${delta_transfers} (Gesamt: ${current_transfers})\n"
            msg+="• 📥 **Downloads:** +${delta_downloads} (Gesamt: ${current_downloads})\n"
            msg+="• ↪️ **Verschiebung:** +${delta_renames} (Gesamt: ${current_renames})\n"
            msg+="• ❌ **Löschungen:** +${delta_deletes} (Gesamt: ${current_deletes})\n"
            msg+="• ⚡ **Geschwindigkeit:** ${speed_mb} MB/s (Modus: ${limit_msg})\n"
            msg+="• 📊 **Fortschritt:** ${percentage} | 🎯 **Restzeit:** ${eta_str}"

            send_discord "$msg"
            
            last_bytes=$current_bytes
            last_deletes=$current_deletes
            last_transfers=$current_transfers
            last_renames=$current_renames
            last_downloads=$current_downloads
        fi
        sleep $MONITOR_INTERVAL
    done
}

run_sync_job() {
    local JOB_SOURCE="$1"
    local JOB_DEST="$2"
    local JOB_FILTER="$3"
    local JOB_NAME="$4"

    echo "--- Starte Job: $JOB_NAME ---" | tee -a "$CURRENT_LOG"
    send_discord "🔄 **Starte Sync-Job:** \`$JOB_NAME\`\nQuelle: \`$JOB_SOURCE\` ➡️ Ziel: \`$JOB_DEST\`"

    EXTRA_FLAGS="--fast-list"
    if [ "$DRY_RUN" = true ]; then EXTRA_FLAGS="$EXTRA_FLAGS --dry-run"; fi

    for attempt in {1..5}; do
        ensure_container_running
        
        docker exec $DOCKER_NAME sh -c 'pkill -f "rclone sync" || true' >/dev/null 2>&1
        sleep 3

        if [ $attempt -eq 5 ]; then
            DELETE_FLAG=""; send_discord "ℹ️ **Massenlöschung Job $JOB_NAME:** Sicherheitszeit abgelaufen. Löschung autorisiert."
        else
            DELETE_FLAG="--max-delete $MAX_DELETE_LIMIT"
        fi

        local CURRENT_HOUR=$(date +%H)
        local RUN_LIMIT="$SPEED_DAY"
        if [ "$CURRENT_HOUR" -ge "$START_NIGHT_HOUR" ] && [ "$CURRENT_HOUR" -lt "$END_NIGHT_HOUR" ]; then RUN_LIMIT="$SPEED_NIGHT"; fi

        docker exec $DOCKER_NAME rclone sync "$JOB_SOURCE" "$JOB_DEST" \
            $JOB_FILTER \
            --bwlimit $RUN_LIMIT \
            --drive-chunk-size 128M \
            --buffer-size 64M \
            --transfers 4 \
            --use-mmap \
            --retries 5 \
            --low-level-retries 10 \
            --rc --rc-no-auth --rc-addr :5575 \
            $DELETE_FLAG $EXTRA_FLAGS \
            -v 2>&1 | tee -a "$CURRENT_LOG"
        
        local EXIT_CODE=${PIPESTATUS[0]}

        if [ $EXIT_CODE -eq 0 ]; then
            FINAL_SUMMARY=$(grep -E "Transferred:|Errors:|Checks:|Deleted:|Renamed:|Elapsed time:" "$CURRENT_LOG" | tail -n 7)
            send_discord "✅ **Job Abgeschlossen:** \`$JOB_NAME\`\n\`\`\`text\n${FINAL_SUMMARY}\n\`\`\`"
            break
        fi

        if grep -q -i "max-delete threshold reached" "$CURRENT_LOG"; then
            if [ $attempt -lt 5 ]; then
                send_discord "⚠️ **Achtung ($JOB_NAME):** Mehr als $MAX_DELETE_LIMIT Löschungen! Warte 5 Minuten... (Versuch $attempt/5)"
                sleep 300
            fi
        else
            echo "[WARN] Job abgebrochen mit Code $EXIT_CODE. Versuche erneuten Durchlauf..." | tee -a "$CURRENT_LOG"
            sleep 10
        fi
    done
}

echo "--- Backup-Start: $(date) ---" | tee "$CURRENT_LOG"
ensure_container_running
hourly_monitor &
MONITOR_PID=$!

trap '
    kill $MONITOR_PID 2>/dev/null; 
    rm -f "$LOCK_FILE" 2>/dev/null;
    if [ "$FTP_WAS_OFF" = true ]; then
        /etc/rc.d/rc.vsftpd stop >/dev/null 2>&1;
    fi
    if [ "$DOCKER_WAS_OFF" = true ]; then
        docker stop "$DOCKER_NAME" >/dev/null 2>&1;
    fi
' EXIT

INITIAL_HOUR=$(date +%H)
if [ "$INITIAL_HOUR" -ge "$START_NIGHT_HOUR" ] && [ "$INITIAL_HOUR" -lt "$END_NIGHT_HOUR" ]; then 
    if [ "$SPEED_NIGHT" = "0" ]; then START_LIMIT="Unbegrenzt 🚀"; else START_LIMIT="${SPEED_NIGHT} 🚀"; fi
else 
    START_LIMIT="${SPEED_DAY} 🐌"
fi

send_discord "🚀 **Backup-Skript gestartet!** Prüfe aktivierte Jobs (Start-Modus: $START_LIMIT)..."

if [ "$JOB1_ENABLE" = true ]; then run_sync_job "$JOB1_SOURCE" "$JOB1_DEST" "$JOB1_FILTER" "$JOB1_NAME"; fi
if [ "$JOB2_ENABLE" = true ]; then run_sync_job "$JOB2_SOURCE" "$JOB2_DEST" "$JOB2_FILTER" "$JOB2_NAME"; fi
if [ "$JOB3_ENABLE" = true ]; then run_sync_job "$JOB3_SOURCE" "$JOB3_DEST" "$JOB3_FILTER" "$JOB3_NAME"; fi

TOTAL_END_TIME=$(date +%s)
TOTAL_DUR=$((TOTAL_END_TIME - START_TIME))

if [ "$DOCKER_WAS_OFF" = true ]; then
    DOCKER_END_MSG="🛑 *Docker-Container wurde wieder gestoppt (war anfangs aus).*"
else
    DOCKER_END_MSG="🟢 *Docker-Container bleibt aktiv (war anfangs bereits an).*"
fi

send_discord "🏁 **Gesamtes Backup beendet!** Alle aktivierten Jobs wurden abgearbeitet. (Gesamtdauer: $((TOTAL_DUR / 3600))h $(((TOTAL_DUR % 3600) / 60))m)\n$DOCKER_END_MSG"
