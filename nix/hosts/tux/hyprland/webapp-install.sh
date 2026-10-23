# webapp-install NAME URL [ICON_URL]
#
# Adds a launcher entry that opens URL in a Chromium app window. Without an icon
# URL it takes the site's favicon from DuckDuckGo. The entry is called
# webapp-<name>, which is how the launcher and webapp-remove find it again.

name="$1"
url="$2"
icon_url="${3:-}"

[[ "$url" == http://* || "$url" == https://* ]] || url="https://$url"
host=$(sed -E 's#^https?://([^/:]+).*#\1#' <<<"$url")
slug=$(tr '[:upper:]' '[:lower:]' <<<"$name" | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')

data="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$data/applications" "$data/icons/webapps"

# DuckDuckGo often has no icon for a subdomain (web.whatsapp.com), so the
# parent domain is the fallback.
if [[ -n "$icon_url" ]]; then
  icon_urls=("$icon_url")
else
  icon_urls=("https://icons.duckduckgo.com/ip3/$host.ico" "https://icons.duckduckgo.com/ip3/${host#*.}.ico")
fi

icon="applications-internet"
for candidate in "${icon_urls[@]}"; do
  # Keep the format in the name: Qt picks the image reader by extension.
  ext="${candidate##*.}"
  ext="${ext%%\?*}"
  [[ "$ext" =~ ^(png|svg|ico|jpg|jpeg|webp)$ ]] || ext=png
  if curl -fsSL -o "$data/icons/webapps/$slug.$ext" "$candidate"; then
    icon="$data/icons/webapps/$slug.$ext"
    break
  fi
done

# Exec treats % as the start of a field code.
cat >"$data/applications/webapp-$slug.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=$url
Exec=chromium --app=${url//%/%%}
Icon=$icon
Categories=Network;
EOF

notify-send "Web app installed" "$name" || true
