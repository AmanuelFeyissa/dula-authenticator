#!/usr/bin/env bash
#
# Builds the three Linux distribution formats ADR-0008 selected — AppImage,
# .deb and .rpm — from one `flutter build linux --release` output. Packaging is
# a wrapping step around an already-working build, not a second build.
#
#   ./packaging/linux/build-packages.sh              # all three
#   ./packaging/linux/build-packages.sh deb appimage # a subset
#
# Flatpak is a deferred stretch goal and Snap is permanently out of scope; see
# ADR-0008 for why. Results land in dist/.
set -euo pipefail

readonly APP_ID="com.dulaauth.totp"
readonly PKG_NAME="dula-authenticator"   # Debian-style: lowercase, hyphenated
readonly BINARY="dula_auth"              # as produced by the Flutter build
readonly MAINTAINER="Amanuel Feyissa Kussa <amanuelfeyissa45@gmail.com>"
readonly HOMEPAGE="https://github.com/AmanuelFeyissa/dula-authenticator"
readonly SUMMARY="Offline TOTP and HOTP authenticator"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
bundle="${root}/build/linux/x64/release/bundle"
dist="${root}/dist"
work="${root}/build/packaging"

# `1.0.0+1` in pubspec is an app version plus a build number; package managers
# want the former only.
version="$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' "${root}/pubspec.yaml")"
[[ -n "${version}" ]] || { echo "could not read version from pubspec.yaml" >&2; exit 1; }

if [[ ! -x "${bundle}/${BINARY}" ]]; then
  echo "No Linux build at ${bundle}." >&2
  echo "Run: flutter build linux --release" >&2
  exit 1
fi

formats=("$@")
[[ ${#formats[@]} -gt 0 ]] || formats=(appimage deb rpm)

rm -rf "${work}"
mkdir -p "${work}" "${dist}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required tool: $1 ($2)" >&2; exit 1; }
}

# ---------------------------------------------------------------------------
# One staged tree, shared by all three formats.
#
# The whole Flutter bundle goes to /usr/lib/<pkg>/ because the executable
# resolves its `data/` directory and its bundled `lib/*.so` relative to its own
# location — splitting them apart breaks asset loading. /usr/bin therefore gets
# a relative symlink rather than the binary itself.
# ---------------------------------------------------------------------------
stage="${work}/stage"
mkdir -p "${stage}/usr/lib/${PKG_NAME}" \
         "${stage}/usr/bin" \
         "${stage}/usr/share/applications" \
         "${stage}/usr/share/metainfo" \
         "${stage}/usr/share/doc/${PKG_NAME}"

cp -a "${bundle}/." "${stage}/usr/lib/${PKG_NAME}/"
ln -sf "../lib/${PKG_NAME}/${BINARY}" "${stage}/usr/bin/${PKG_NAME}"
install -m644 "${here}/${APP_ID}.desktop" "${stage}/usr/share/applications/"
install -m644 "${here}/${APP_ID}.metainfo.xml" "${stage}/usr/share/metainfo/"
install -m644 "${root}/LICENSE" "${stage}/usr/share/doc/${PKG_NAME}/copyright"
install -m644 "${root}/NOTICE" "${stage}/usr/share/doc/${PKG_NAME}/NOTICE"

for size in 512 256 128 64 48 32; do
  d="${stage}/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "${d}"
  install -m644 "${here}/icons/${size}.png" "${d}/${APP_ID}.png"
done

echo "staged ${PKG_NAME} ${version} from ${bundle}"

# ---------------------------------------------------------------------------
# .deb
# ---------------------------------------------------------------------------
build_deb() {
  need dpkg-deb "apt-get install dpkg-dev"
  local debroot="${work}/deb"
  cp -a "${stage}" "${debroot}"
  mkdir -p "${debroot}/DEBIAN"

  # Alternatives cover Debian/Ubuntu's 64-bit time_t transition, which renamed
  # several runtime packages with a `t64` suffix; naming only the old ones
  # makes the package uninstallable on Ubuntu 24.04 and newer.
  #
  # libegl1/libgles2 are not discoverable automatically. The bundle links
  # libepoxy, and epoxy dlopen()s libEGL.so.1 and libGLESv2.so.2 at runtime —
  # so neither dpkg-shlibdeps nor rpm's generator sees them, and they are not
  # even named in our own binaries' strings. Omitting them installs fine and
  # then aborts at launch with "Couldn't open libGLESv2.so.2", which is how
  # this was found: on a minimal Fedora, not on a dev box where the GL stack
  # is already present as a build dependency.
  #
  # gnome-keyring is Recommends, not Depends: the app needs *a* Secret Service
  # implementation (ADR-0004), any of several provide one, and it degrades to a
  # clear blocking error rather than misbehaving when none is present
  # (ADR-0018).
  cat > "${debroot}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${version}
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0 | libgtk-3-0t64, libsecret-1-0, libglib2.0-0 | libglib2.0-0t64, libegl1, libgles2
Recommends: gnome-keyring | kwalletmanager | keepassxc
Maintainer: ${MAINTAINER}
Homepage: ${HOMEPAGE}
Description: ${SUMMARY}
 Generates TOTP (RFC 6238) and HOTP (RFC 4226) codes entirely on the device.
 There is no backend, no account and no telemetry of any kind, so it works on
 air-gapped and restricted networks.
 .
 Secrets are sealed with AES-256-GCM under an Argon2id-derived key and kept in
 the system Secret Service, so a keyring daemon must be installed and unlocked.
EOF

  dpkg-deb --root-owner-group --build "${debroot}" \
    "${dist}/${PKG_NAME}_${version}_amd64.deb" >/dev/null
  echo "built ${dist}/${PKG_NAME}_${version}_amd64.deb"
}

# ---------------------------------------------------------------------------
# .rpm
# ---------------------------------------------------------------------------
build_rpm() {
  need rpmbuild "apt-get install rpm"
  local top="${work}/rpm"
  mkdir -p "${top}"/{BUILD,RPMS,SPECS}

  # %install copies the staged tree rather than compiling: the binary is
  # already built, and rpmbuild is used purely to wrap it.
  cat > "${top}/SPECS/${PKG_NAME}.spec" <<EOF
Name:           ${PKG_NAME}
Version:        ${version}
Release:        1
Summary:        ${SUMMARY}
License:        Apache-2.0
URL:            ${HOMEPAGE}
BuildArch:      x86_64
Requires:       gtk3
Requires:       libsecret
# By soname, so any provider satisfies it across Fedora/RHEL/openSUSE. These
# are dlopen'd by libepoxy rather than linked, so rpm cannot infer them; see
# the .deb control above for the full story.
Requires:       libEGL.so.1()(64bit)
Requires:       libGLESv2.so.2()(64bit)
Recommends:     gnome-keyring
# The Flutter engine ships stripped, prebuilt .so files; RPM's own debuginfo
# extraction has nothing to work with and only fails the build.
%global debug_package %{nil}
%define _build_id_links none

%description
Generates TOTP (RFC 6238) and HOTP (RFC 4226) codes entirely on the device.
There is no backend, no account and no telemetry of any kind, so it works on
air-gapped and restricted networks.

Secrets are sealed with AES-256-GCM under an Argon2id-derived key and kept in
the system Secret Service, so a keyring daemon must be installed and unlocked.

%install
cp -a ${stage}/. %{buildroot}/

%files
/usr/lib/${PKG_NAME}
/usr/bin/${PKG_NAME}
/usr/share/applications/${APP_ID}.desktop
/usr/share/metainfo/${APP_ID}.metainfo.xml
/usr/share/icons/hicolor/*/apps/${APP_ID}.png
%doc /usr/share/doc/${PKG_NAME}/NOTICE
%license /usr/share/doc/${PKG_NAME}/copyright
EOF

  # rpmbuild narrates its whole %install to stderr; keep it for a failure and
  # out of the way otherwise.
  if ! rpmbuild --define "_topdir ${top}" -bb "${top}/SPECS/${PKG_NAME}.spec" \
       > "${work}/rpmbuild.log" 2>&1; then
    cat "${work}/rpmbuild.log" >&2
    exit 1
  fi
  find "${top}/RPMS" -name '*.rpm' -exec cp {} "${dist}/" \;
  echo "built $(find "${dist}" -name "${PKG_NAME}-${version}*.rpm" -print -quit)"
}

# ---------------------------------------------------------------------------
# AppImage — ADR-0008's primary format: one file, no install step, no network.
# ---------------------------------------------------------------------------
build_appimage() {
  need appimagetool "https://github.com/AppImage/appimagetool/releases"
  # appimagetool shells out to both of these and only reports them missing
  # once it is already running, so check up front: the failure then names the
  # package to install instead of surfacing from inside the tool.
  need file "apt-get install file"
  need desktop-file-validate "apt-get install desktop-file-utils"
  local appdir="${work}/AppDir"
  cp -a "${stage}" "${appdir}"

  # appimagetool wants the desktop entry and its icon at the AppDir root, in
  # addition to the usual /usr/share locations kept above.
  install -m644 "${here}/${APP_ID}.desktop" "${appdir}/${APP_ID}.desktop"
  install -m644 "${here}/icons/256.png" "${appdir}/${APP_ID}.png"

  cat > "${appdir}/AppRun" <<EOF
#!/bin/sh
# Resolve through any symlink the user made, so the payload is found whatever
# the AppImage itself was renamed to.
HERE="\$(dirname "\$(readlink -f "\$0")")"
exec "\${HERE}/usr/lib/${PKG_NAME}/${BINARY}" "\$@"
EOF
  chmod +x "${appdir}/AppRun"

  # appimagetool is itself an AppImage and needs FUSE, which containers and CI
  # runners usually lack; this makes it unpack itself instead.
  APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 \
    appimagetool "${appdir}" "${dist}/Dula_Authenticator-${version}-x86_64.AppImage" >/dev/null
  echo "built ${dist}/Dula_Authenticator-${version}-x86_64.AppImage"
}

for f in "${formats[@]}"; do
  case "${f}" in
    deb)      build_deb ;;
    rpm)      build_rpm ;;
    appimage) build_appimage ;;
    *) echo "unknown format: ${f} (expected appimage, deb or rpm)" >&2; exit 1 ;;
  esac
done

echo
echo "dist/:"
ls -la "${dist}"
