#!/usr/bin/env bash
# Points package.nix at the Linux build of Wing Edit that Behringer's WING
# product page links to. Needs curl and nix.
set -euo pipefail
cd "$(dirname "$0")"

url=$(curl -fsSL https://www.behringer.com/en/wing/wing-black |
  grep -oE 'https://cdn-media\.empowertribe\.com/[0-9a-f]{32}/Wing-Edit_LINUX_[0-9.]+\.tar\.gz' |
  sort -u -t_ -k3,3V | tail -n1) || true
if [ -z "$url" ]; then
  echo "no Wing-Edit_LINUX download on the WING page; has the page changed?" >&2
  exit 1
fi

version=${url##*_}
version=${version%.tar.gz}
current=$(sed -nE 's/^  version = "(.*)";$/\1/p' package.nix)
if [ "$version" = "$current" ]; then
  echo "up to date: $current"
  exit 0
fi

hash=$(nix store prefetch-file --json "$url" | sed -E 's/.*"hash":"([^"]+)".*/\1/')
sed -i -E \
  -e "s|^  version = \".*\";$|  version = \"$version\";|" \
  -e "s|^    url = \".*\";$|    url = \"$url\";|" \
  -e "s|^    hash = \".*\";$|    hash = \"$hash\";|" \
  package.nix
echo "updated: $current -> $version"
