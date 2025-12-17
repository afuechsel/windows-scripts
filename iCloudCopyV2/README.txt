README.txt
==========

Projekt: iCloudCopyV2
Autor: ChatGPT
Datum: 2025-12-17

Ziel
----
Automatisches, inkrementelles Backup von iCloud-Fotos unter Windows
ohne iCloud für Windows.

Komponenten
-----------
1. icloudpd (Download aus iCloud per Web-API)
2. PowerShell Script iCloudCopyV2.ps1 (Sortierung, Deduplikation)

Installation
------------
1. Python installieren (https://www.python.org)
   - During install: "Add Python to PATH" aktivieren

2. icloudpd installieren:
   pip install icloudpd

3. Optional empfohlen:
   - Windows Terminal
   - PowerShell 7+

icloudpd Beispielkonfiguration
------------------------------
icloudpd ^
  --directory "D:\Photos\_incoming" ^
  --username "DEINE_APPLE_ID@mail.de" ^
  --cookie-directory "%APPDATA%\icloudpd" ^
  --size original ^
  --set-exif-datetime ^
  --auto-delete

PowerShell Script
-----------------
Trockenlauf:
  .\iCloudCopyV2.ps1 -WhatIf

Echtlauf:
  .\iCloudCopyV2.ps1

Eigenschaften
--------------
- idempotent
- hash-basiert
- Live-Foto-fähig
- Taskplaner-tauglich

Empfehlung
----------
1. icloudpd regelmäßig ausführen
2. danach iCloudCopyV2.ps1
3. optional Robocopy-Backup

