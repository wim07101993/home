#!/usr/bin/env bash

set -uo pipefail

usage() {
  echo "usage: $0 [-b branch]" >&2
  exit 2
}

branch=main
while getopts b: opt; do
  case $opt in
    b) branch=$OPTARG ;;
    *) usage ;;
  esac
done
[ $OPTIND -gt $# ] || usage

declare -A addr=(
  [bumba]=100.104.241.49
  [mindy]=100.127.106.121
  [samson]=100.71.248.106
  [plop]=100.117.36.52
)

hosts=(bumba mindy samson plop)

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
declare -A status

for host in "${hosts[@]}"; do
  echo "=== updating ${host}"
  ssh "${ssh_opts[@]}" "wim@${addr[$host]}" bash -s -- "$branch" <<'EOF'
set -u
repo=~/source/github/wim07101993/home
git -C "$repo" fetch --quiet origin "$1" && git -C "$repo" checkout --quiet "$1" || exit 1
home-update
EOF
  echo
  rc=$?
  echo "=== updated ${host} (${rc})"
done
