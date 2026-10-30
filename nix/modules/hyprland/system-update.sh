# Pulls this repo and switches to it. Run in a terminal by the launcher, which
# closes when this exits, so it waits for Enter either way.

cd "$HOME/source/github/wim07101993/home"

if git pull --ff-only && sudo nixos-rebuild switch --flake ./nix; then
  echo
  echo "System updated."
else
  echo
  echo "Update failed, see above."
fi

read -rp "Press Enter to close." _
