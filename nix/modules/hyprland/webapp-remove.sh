# webapp-remove webapp-<name>
#
# Removes a launcher entry webapp-install made, and its icon. Refuses any other
# entry.

id="$1"
[[ "$id" == webapp-* ]] || { echo "not a web app: $id" >&2; exit 1; }

data="${XDG_DATA_HOME:-$HOME/.local/share}"
rm -f "$data/applications/$id.desktop" "$data/icons/webapps/${id#webapp-}".*

notify-send "Web app removed" "${id#webapp-}" || true
