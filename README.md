# rclone Multi-Job Master-Sync (Unraid)

An intelligent, robust, and highly automated rclone multi-job backup script for Unraid with time-based bandwidth shaping, smart service state management, and detailed hourly Discord notifications.

---

## 🇩🇪 Deutsche Beschreibung & Anleitung

Hallo zusammen,

ich habe mir vor einiger Zeit Gedanken darüber gemacht, wie ich meine Daten am besten synchronisieren und sichern kann. Eigentlich war das Anfangsskript nur dafür gedacht, meine wichtigsten Ordner auf Google Drive zu spiegeln. Falls mal meine Festplatten im Server und auch mein primärer Speicher defekt gehen sollten, wollte ich meine Fotos und wichtigen Dokumente trotzdem noch sicher in der Cloud wissen.

Ich habe dann viel mit Gemini geschrieben und so kam eine Idee zur nächsten. Aus meinen Ideen hat Gemini dann Schritt für Schritt das umgesetzt, was jetzt hier läuft (hoffe ich zumindest!). Am Ende bin ich genau da gelandet, wo ich jetzt mit dem Skript stehe. Da ich selbst überhaupt nicht programmieren kann, hat Gemini den kompletten Code für mich geschrieben und alle meine Wünsche genauso umgesetzt, wie es jetzt gerade läuft. Da ich glaube, dass es so etwas mit diesen Features in der Unraid-Community noch nicht gibt, wollte ich es unbedingt für euch zur Verfügung stellen – falls jemand von euch ein ähnliches Vorhaben plant!

> ⚠️ **WICHTIGER HINWEIS / HAFTUNGSAUSSCHLUSS:**
> Da ich, wie oben erwähnt, selbst kein Programmierer bin, kann ich den Code im Detail nicht selbst lesen oder überprüfen, sondern nur vermuten, was genau passiert. Ich übernehme daher **absolut keine Haftung oder Garantie** für eventuelle Datenverluste, Fehler oder Schäden an eurem System. Die Nutzung des Skripts erfolgt komplett auf eigene Gefahr! Bitte testet es unbedingt zuerst im integrierten Testmodus (`DRY_RUN=true`).

Es läuft perfekt über das **User Scripts Plugin** und steuert einen rclone-Docker-Container (wie z. B. `Nacho-Rclone-Native-GUI`) an.

### 🌟 Features
* **🧠 Smart-State-Management (FTP & Docker):** Schaltet FTP und den Docker-Container nur fürs Backup an und stellt danach den alten Zustand wieder her.
* **🐌/🚀 Uhrzeitbasierte Bandbreitensteuerung:** Läuft nachts unbegrenzt und drosselt tagsüber automatisch, um das Heimnetzwerk zu schonen.
* **🗂️ Multi-Job-System:** Bis zu 3 verschiedene Sync-Jobs nacheinander ausführen.
* **🧟 Anti-Zombie-Schutz:** Räumt blockierte Ports und hängengebliebene Docker-Prozesse beim Neustart automatisch auf.
* **🌐 Pre-Flight-Checks:** Wartet beim Booten bis zu 60 Sekunden auf das Netzwerk und bricht bei Cloud-Ausfällen sicher ab.
* **📊 Discord-Live-Stats:** Stündliche detaillierte Status-Updates (Uploads, Downloads, Verschiebungen, Löschungen, aktuelle Geschwindigkeit und Fortschritt).

### 🛠️ Installation & Einrichtung
1. **NerdTools-Plugin** in Unraid installieren und das Paket `jq` aktivieren (wichtig für die API-Statistiken!).
2. Ein neues Skript im **User Scripts Plugin** anlegen.
3. Den Code aus der Datei `rclone_master_sync.sh` hineinkopieren.
4. Nur den oberen `⚙️ EINSTELLUNGEN`-Block nach eigenen Wünschen anpassen (Discord-Webhook, Pfade, Zeiten). Speicher und fertig!

---

## 🇺🇸 English Description & Guide

Hello everyone,

A while ago, I was thinking about the best way to synchronize and secure my data. Initially, the original script was only meant to mirror my most important folders to Google Drive. Just in case my server's hard drives and my primary storage should ever fail at the same time, I wanted to know that my photos and important documents were still safe in the cloud.

I ended up chatting a lot with Gemini, and one idea led to another. Step by step, Gemini turned my ideas into what is running here today (at least I hope so!). In the end, I landed exactly where I am now with this script. Since I don't know how to program at all, Gemini wrote the entire code for me and implemented all my wishes exactly the way it is running right now. Because I believe that something with these specific features does not yet exist in the Unraid community, I really wanted to make it available to you – in case anyone out there is planning a similar project!

> ⚠️ **IMPORTANT NOTICE / DISCLAIMER:**
> As mentioned above, I am not a programmer myself. I cannot read or verify the technical details of the code, so I can only assume how Gemini built certain parts of it. Therefore, I assume **absolutely no liability or responsibility** for any data loss, errors, or damage to your system. Use this script entirely at your own risk! Please make sure to test it first using the built-in test mode (`DRY_RUN=true`).

It runs perfectly via the **User Scripts Plugin** and controls an rclone Docker container (such as `Nacho-Rclone-Native-GUI`).

### 🌟 Features
* **🧠 Smart State Management (FTP & Docker):** Starts FTP and the Docker container only for the backup and restores their original state afterwards.
* **🐌/🚀 Time-Based Bandwidth Control:** Runs unlimited at night and automatically throttles during the day to save network bandwidth.
* **🗂️ Multi-Job System:** Run up to 3 sync jobs sequentially.
* **🧟 Anti-Zombie Protection:** Automatically cleans up blocked ports and stuck Docker processes upon script restart.
* **🌐 Pre-Flight Checks:** Waits for network on boot (up to 60s) and safely aborts if cloud servers are unreachable.
* **📊 Discord Live Stats:** Hourly detailed status updates (Uploads, Downloads, Renames, Deletions, Current Speed, and Progress).

### 🛠️ Installation & Setup
1. Install the **NerdTools** plugin in Unraid and enable the `jq` package (crucial for reading API stats!).
2. Create a new script inside the **User Scripts Plugin**.
3. Copy the code from `rclone_master_sync.sh` into it.
4. Only adjust the upper `⚙️ SETTINGS` block to your needs (Webhook, paths, times). Save and enjoy!
