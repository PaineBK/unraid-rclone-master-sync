#!/bin/bash
# rclone Master-Sync: Unraid -> Remote Cloud
# Features: Multi-Job, Fast-List, Anti-Zombie, Discord-Stats, Bandwidth-Control, Network-Check, Cloud-Check, Smart-FTP, Smart-Docker
# Author: Unraid Community Member

# ==========================================
# ⚙️ SETTINGS (EDIT EVERYTHING HERE)
# ==========================================

# --- SYSTEM & DISCORD ---

# Enter the exact name of your rclone Docker container here (case-sensitive!)
DOCKER_NAME="Nacho-Rclone-Native-GUI" 

# Paste your Discord Webhook link here to receive status notifications
DISCORD_WEBHOOK="INSERT_YOUR_DISCORD_WEBHOOK_HERE"

# The path where the script should save its log files (created automatically)
LOG_DIR="/mnt/user/appdata/rclone/logs"


# --- SPEED & BANDWIDTH CONTROL ---

# From what time at night should the script run at full speed? (Value between 0 and 23)
START_NIGHT_HOUR=1     

# Until what time in the morning should the unlimited speed apply? (Value between 0 and 23)
END_NIGHT_HOUR=5       

# How fast can the upload be DURING THE DAY? (So your home internet does not get choked)
SPEED_DAY="1M"         

# How fast can the upload be AT NIGHT? ("0" means absolutely unlimited)
SPEED_NIGHT="0"        


# --- EFFICIENCY & SAFETY LIMITS ---

# Every how many seconds should a live status update be posted to Discord? (3600 = every hour)
MONITOR_INTERVAL=3600  

# Mass Deletion Protection: At how many deleted files should the script stop and pause for 5 minutes?
MAX_DELETE_LIMIT=50    

# TEST MODE: If set to "true", the script will only simulate the backup (no uploading or deleting).
DRY_RUN=false          


# ------------------------------------------
# 🚀 YOUR BACKUP JOBS (SYNC JOBS)
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
# 🛠️ SYSTEM CODE (DO NOT CHANGE ANYTHING BELOW THIS LINE)
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
    echo "[ERROR] No general internet connection after 60 seconds. Aborting."
    exit 1
fi

if ! ping -c 1 drive.google.com >/dev/null 2>&1; then
    echo "[ERROR] Cloud server unreachable. Aborting before starting services."
    send_discord "🚨 **Backup Blocked:** The cloud servers are currently unreachable or there is a DNS issue. The script was aborted safely."
    exit 1
fi

LOCK_FILE="/tmp/rclone_backup.lock"

if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE")
    if ps -p $PID > /dev/null; then
        echo "[ERROR] Backup is already running with PID $PID. Aborting."
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
    echo "[INFO] FTP server is disabled. Starting vsftpd temporarily..." | tee -a "$CURRENT_LOG"
    /etc/rc.d/rc.vsftpd start >/dev/null 2>&1
    sleep 3
fi

DOCKER_WAS_OFF=false
if [ "$(docker inspect -f '{{.State.Running}}' "$DOCKER_NAME" 2>/dev/null)" != "true" ]; then
    DOCKER_WAS_OFF=true
    echo "[INFO] Docker container was disabled. Starting it for the backup..." | tee -a "$CURRENT_LOG"
fi

ensure_container_running() {
    if [ "$(docker inspect -f '{{.State.Running}}' "$DOCKER_NAME" 2>/dev/null)" != "true" ]; then
        echo "[INFO] Docker container $DOCKER_NAME is offline. Starting container..." | tee -a "$CURRENT_LOG"
        send_discord "⚙️ **Info:** Docker container \`$DOCKER_NAME\` was stopped. Restarting automatically..."
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
            if [ "$SPEED_NIGHT" = "0" ]; then limit_msg="Unlimited 🚀"; else limit_msg="${SPEED_NIGHT} 🚀"; fi
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
            
            if [ "$percentage" = "null" ] || [ -z "$percentage" ]; then percentage="Unknown"; else percentage="${percentage}%"; fi
            
            local eta_str="Unknown"
            if [ "$eta_seconds" != "null" ] && [ "$eta_seconds" -gt 0 ] 2>/dev/null; then
                eta_str="$((eta_seconds / 3600))h $(((eta_seconds % 3600) / 60))m"
            fi

            local now=$(date +%s); local elapsed_sec=$((now - START_TIME))
            local elapsed_str="$((elapsed_sec / 3600))h $(((elapsed_sec % 3600) / 60))m"

            local msg="⏳ **Hourly Backup Update**\n"
            msg+="• ⏱️ **Time elapsed:** ${elapsed_str}\n"
            msg+="• 📦 **Total transferred:** ${total_gb} GB (+${delta_gb} GB last hr.)\n"
            msg+="• 📤 **Uploads:** +${delta_transfers} (Total: ${current_transfers})\n"
            msg+="• 📥 **Downloads:** +${delta_downloads} (Total: ${current_downloads})\n"
            msg+="• ↪️ **Renames:** +${delta_renames} (Total: ${current_renames})\n"
            msg+="• ❌ **Deletions:** +${delta_deletes} (Total: ${current_deletes})\n"
            msg+="• ⚡ **Speed:** ${speed_mb} MB/s (Mode: ${limit_msg})\n"
            msg+="• 📊 **Progress:** ${percentage} | 🎯 **ETA:** ${eta_str}"

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

    echo "--- Starting Job: $JOB_NAME ---" | tee -a "$CURRENT_LOG"
    send_discord "🔄 **Starting Sync Job:** \`$JOB_NAME\`\nSource: \`$JOB_SOURCE\` ➡️ Destination: \`$JOB_DEST\`"

    EXTRA_FLAGS="--fast-list"
    if [ "$DRY_RUN" = true ]; then EXTRA_FLAGS="$EXTRA_FLAGS --dry-run"; fi

    for attempt in {1..5}; do
        ensure_container_running
        
        docker exec $DOCKER_NAME sh -c 'pkill -f "rclone sync" || true' >/dev/null 2>&1
        sleep 3

        if [ $attempt -eq 5 ]; then
            DELETE_FLAG=""; send_discord "ℹ️ **Mass Deletion Job $JOB_NAME:** Safety delay expired. Deletion authorized."
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
            send_discord "✅ **Job Completed:** \`$JOB_NAME\`\n\`\`\`text\n${FINAL_SUMMARY}\n\`\`\`"
            break
        fi

        if grep -q -i "max-delete threshold reached" "$CURRENT_LOG"; then
            if [ $attempt -lt 5 ]; then
                send_discord "⚠️ **Attention ($JOB_NAME):** More than $MAX_DELETE_LIMIT deletions detected! Hold triggered. Waiting 5 minutes... (Attempt $attempt/5)"
                sleep 300
            fi
        else
            echo "[WARN] Job aborted with code $EXIT_CODE. Retrying run..." | tee -a "$CURRENT_LOG"
            sleep 10
        fi
    done
}

echo "--- Backup Start: $(date) ---" | tee "$CURRENT_LOG"
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
    if [ "$SPEED_NIGHT" = "0" ]; then START_LIMIT="Unlimited 🚀"; else START_LIMIT="${SPEED_NIGHT} 🚀"; fi
else 
    START_LIMIT="${SPEED_DAY} 🐌"
fi

send_discord "🚀 **Backup Script Started!** Processing enabled jobs (Initial Mode: $START_LIMIT)..."

if [ "$JOB1_ENABLE" = true ]; then run_sync_job "$JOB1_SOURCE" "$JOB1_DEST" "$JOB1_FILTER" "$JOB1_NAME"; fi
if [ "$JOB2_ENABLE" = true ]; then run_sync_job "$JOB2_SOURCE" "$JOB2_DEST" "$JOB2_FILTER" "$JOB2_NAME"; fi
if [ "$JOB3_ENABLE" = true ]; then run_sync_job "$JOB3_SOURCE" "$JOB3_DEST" "$JOB3_FILTER" "$JOB3_NAME"; fi

TOTAL_END_TIME=$(date +%s)
TOTAL_DUR=$((TOTAL_END_TIME - START_TIME))

if [ "$DOCKER_WAS_OFF" = true ]; then
    DOCKER_END_MSG="🛑 *Docker container was stopped automatically (was originally off).*"
else
    DOCKER_END_MSG="🟢 *Docker container remains active (was originally already on).*"
fi

send_discord "🏁 **Entire Backup Finished!** All enabled jobs have been processed. (Total Duration: $((TOTAL_DUR / 3600))h $(((TOTAL_DUR % 3600) / 60))m)\n$DOCKER_END_MSG"
