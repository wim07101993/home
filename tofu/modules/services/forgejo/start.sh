set -e

# The admin account. The installer would create it, but INSTALL_LOCK skips the
# installer, so it is made here once and its password is reset from tofu on
# every start after that.
forgejo migrate
if forgejo admin user list --admin | awk 'NR > 1 { print $2 }' | grep -qx wim; then
  forgejo admin user change-password --username wim --password "$ADMIN_PASSWORD" --must-change-password=false
else
  forgejo admin user create --admin --username wim --email wim@wvl.app --password "$ADMIN_PASSWORD" --must-change-password=false
fi

exec forgejo web
