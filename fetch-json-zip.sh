#!/usr/bin/env bash
# --------------------------------------------------------------
# fetch-json-zip.sh – Pull a sensitive .json file from a VPS,
# zip it with a password, and expose a data‑URI link that the
# user can click to download *the encrypted ZIP*.
#
# Usage (in your vendor’s one‑page shell console):
#   bash fetch-json-zip.sh
# --------------------------------------------------------------

set -euo pipefail

###########################
## 1️⃣ USER SETTINGS
###########################

JSON_PATH="/path/to/file.json"      # <-- replace with the real location on the VPS
ZIP_PASS="SuperSecretPassword123!" # <-- change to a *secure* password of your choice

###########################
## 2️⃣ CREATE TEMPORARY AREA
###########################

# A writable, isolated directory – you can also use /tmp directly.
TMP_DIR=$(mktemp -d /tmp/vps_fetch_XXXXXX)

echo "[+] Using temp dir: $TMP_DIR"

###########################
## 3️⃣ ZIP WITH PASSWORD
###########################

# zip -e creates a password‑protected archive; the `-P` flag is for the password.
zip -P "$ZIP_PASS" "$TMP_DIR/file.zip" "$JSON_PATH"
echo "[+] Created password‑protected ZIP: $TMP_DIR/file.zip"

###########################
## 4️⃣ BASE64 EINN (no line breaks)
###########################

# `base64 -w0` writes the output on a single line – perfect for data‑URI.
BASE64_ZIP=$(base64 -w0 "$TMP_DIR/file.zip")
echo "[+] Base64‑encoded ZIP ready."

###########################
## 5️⃣ BUILD DATA‑URI LINK
###########################

cat <<EOF
<!DOCTYPE html>
<html lang="fa">
<head><meta charset="utf-8"></head>
<body style="font-family:Arial,Helvetica,sans-serif;text-align:center;margin-top:2rem;">
  <h3>دانلود فایل زیپ‌شده و رمزنگاری‌شده</h3>
  <a href="data:application/zip;base64,$BASE64_ZIP"
     download="file.zip"
     style="display:inline-block;padding:.75rem 1.5rem;background:#337ab7;color:white;text-decoration:none;border-radius:.25rem;">
    دانلود زیپ
  </a>
</body>
</html>
EOF

###########################
## 6️⃣ OPTIONAL: CLEAN UP TEMP DIR
###########################

# The script ends here – the temp dir can be removed manually if you like.
# rm -rf "$TMP_DIR"
