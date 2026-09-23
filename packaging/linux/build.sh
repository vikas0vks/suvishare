#!/usr/bin/env bash
# Builds Suvi Share for Linux and packages it as a .tar.gz and a .deb.
#
# Run on a Linux machine (or WSL) with the Flutter SDK and the desktop
# prerequisites installed:
#   apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
#
# Usage:  packaging/linux/build.sh [flutter-bin-dir]
# Output: packaging/linux/output/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/app"
OUT_DIR="$SCRIPT_DIR/output"

FLUTTER_BIN="${1:-}"
if [[ -n "$FLUTTER_BIN" ]]; then
  export PATH="$FLUTTER_BIN:$PATH"
fi
command -v flutter >/dev/null || { echo "flutter not on PATH"; exit 1; }

VERSION="$(grep '^version:' "$APP_DIR/pubspec.yaml" | sed 's/version: *//; s/+.*//')"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
echo "== Suvi Share $VERSION ($ARCH) =="

cd "$APP_DIR"
flutter pub get
flutter build linux --release

# Locate the bundle rather than hardcoding the path — its layout has moved
# between Flutter versions (x64/release/bundle vs release/bundle).
BUNDLE="$(dirname "$(find "$APP_DIR/build/linux" -type f -name suvi_share \
    -not -path '*intermediates*' | head -n 1)")"
[[ -n "$BUNDLE" && -x "$BUNDLE/suvi_share" ]] || {
  echo "bundle missing under $APP_DIR/build/linux"; exit 1;
}
echo "bundle: $BUNDLE"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------- tar.gz ----
TAR_STAGE="$OUT_DIR/stage-tar/suvi-share-$VERSION"
mkdir -p "$TAR_STAGE"
cp -r "$BUNDLE/." "$TAR_STAGE/"
cp "$SCRIPT_DIR/suvi-share.desktop" "$TAR_STAGE/"
cp "$APP_DIR/assets/icon/suvi-share-256.png" "$TAR_STAGE/suvi-share.png"
cat > "$TAR_STAGE/install.sh" <<'EOS'
#!/usr/bin/env bash
# Installs Suvi Share for the current user (no root needed).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.local/opt/suvi-share"
mkdir -p "$TARGET" "$HOME/.local/bin" \
         "$HOME/.local/share/applications" \
         "$HOME/.local/share/icons/hicolor/256x256/apps"
cp -r "$DIR/." "$TARGET/"
ln -sf "$TARGET/suvi_share" "$HOME/.local/bin/suvi-share"
sed "s|^Exec=.*|Exec=$TARGET/suvi_share|" "$DIR/suvi-share.desktop" \
    > "$HOME/.local/share/applications/suvi-share.desktop"
cp "$DIR/suvi-share.png" "$HOME/.local/share/icons/hicolor/256x256/apps/suvi-share.png"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Installed. Launch 'Suvi Share' from your app menu (or run suvi-share)."

# Try to open the firewall ports automatically (needs sudo). Without inbound
# 53317/53318 this machine cannot be seen and cannot receive.
if command -v ufw >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    sudo ufw allow 53317/tcp comment 'Suvi Share' >/dev/null 2>&1 || true
    sudo ufw allow 53317/udp comment 'Suvi Share discovery' >/dev/null 2>&1 || true
    sudo ufw allow 53318/tcp comment 'Suvi Share web' >/dev/null 2>&1 || true
    echo "Firewall: opened 53317 (tcp/udp) and 53318 (tcp) in ufw."
  fi
else
  echo "IMPORTANT: if a firewall is on, other devices cannot reach this"
  echo "machine until you open the ports:"
  echo "  ufw:        sudo ufw allow 53317/tcp && sudo ufw allow 53317/udp && sudo ufw allow 53318/tcp"
  echo "  firewalld:  sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp --add-port=53318/tcp && sudo firewall-cmd --reload"
fi
EOS
chmod +x "$TAR_STAGE/install.sh" "$TAR_STAGE/suvi_share"
tar -C "$OUT_DIR/stage-tar" -czf "$OUT_DIR/SuviShare-$VERSION-linux-x64.tar.gz" \
    "suvi-share-$VERSION"

# ------------------------------------------------------------------- .deb ---
# Stage Debian control files on the native Linux filesystem. Windows DrvFS
# reports broad synthetic permissions that dpkg-deb intentionally rejects.
DEB_STAGE="$(mktemp -d -t suvi-share-deb.XXXXXX)"
trap 'rm -rf "$DEB_STAGE"' EXIT
PKG_DIR="$DEB_STAGE/suvi-share_${VERSION}_${ARCH}"
mkdir -p "$PKG_DIR/DEBIAN" \
         "$PKG_DIR/usr/lib/suvi-share" \
         "$PKG_DIR/usr/bin" \
         "$PKG_DIR/usr/share/applications" \
         "$PKG_DIR/usr/share/icons/hicolor/256x256/apps"
# DrvFS and some CI workspaces can report newly created directories as 0777;
# dpkg-deb correctly rejects an overly writable control directory.
chmod 0755 "$PKG_DIR/DEBIAN"
cp -r "$BUNDLE/." "$PKG_DIR/usr/lib/suvi-share/"
ln -s /usr/lib/suvi-share/suvi_share "$PKG_DIR/usr/bin/suvi-share"
cp "$SCRIPT_DIR/suvi-share.desktop" "$PKG_DIR/usr/share/applications/"
cp "$APP_DIR/assets/icon/suvi-share-256.png" \
   "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/suvi-share.png"

INSTALLED_SIZE=$(du -sk "$PKG_DIR/usr" | cut -f1)
cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: suvi-share
Version: $VERSION
Architecture: $ARCH
Maintainer: vikas0vks <noreply@suvishare.local>
Installed-Size: $INSTALLED_SIZE
Depends: libgtk-3-0, libayatana-appindicator3-1 | libappindicator3-1
Section: net
Priority: optional
Homepage: https://github.com/vikas0vks/suvishare
Description: Share files across your Wi-Fi. No cloud, no account.
 Suvi Share moves files, photos, videos and text between devices on the
 same network - Android, Windows, Linux and any web browser. Transfers
 are TLS-encrypted and never leave the LAN.
EOF
cat > "$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true

# Open the Suvi Share ports when a firewall is active — the same courtesy the
# Windows installer extends. Without inbound 53317 (API + discovery replies)
# and 53318 (web share) this machine is invisible to every other device,
# which users experience as "Linux detects nothing and receives nothing".
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 53317/tcp comment 'Suvi Share' >/dev/null 2>&1 || true
  ufw allow 53317/udp comment 'Suvi Share discovery' >/dev/null 2>&1 || true
  ufw allow 53318/tcp comment 'Suvi Share web' >/dev/null 2>&1 || true
  echo "Suvi Share: opened ports 53317 (tcp/udp) and 53318 (tcp) in ufw."
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=53317/tcp >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port=53317/udp >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port=53318/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  echo "Suvi Share: opened ports 53317 (tcp/udp) and 53318 (tcp) in firewalld."
fi
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postinst"

cat > "$PKG_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/sh
# Best-effort removal of the firewall rules added by postinst.
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
  if command -v ufw >/dev/null 2>&1; then
    ufw delete allow 53317/tcp >/dev/null 2>&1 || true
    ufw delete allow 53317/udp >/dev/null 2>&1 || true
    ufw delete allow 53318/tcp >/dev/null 2>&1 || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --remove-port=53317/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --remove-port=53317/udp >/dev/null 2>&1 || true
    firewall-cmd --permanent --remove-port=53318/tcp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
fi
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postrm"
dpkg-deb --build --root-owner-group "$PKG_DIR" \
    "$OUT_DIR/suvi-share_${VERSION}_${ARCH}.deb"

rm -rf "$OUT_DIR/stage-tar" "$DEB_STAGE"
trap - EXIT
echo
echo "== Artifacts =="
ls -lh "$OUT_DIR"
sha256sum "$OUT_DIR"/* | sed "s|$OUT_DIR/||"
