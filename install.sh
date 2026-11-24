#!/bin/sh
# install.sh — link bin/orchestra into a directory on PATH.
# Usage: ./install.sh [--prefix DIR]   (default: $HOME/.local/bin)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
prefix=$HOME/.local/bin

while [ $# -gt 0 ]; do
  case $1 in
    --prefix)
      [ $# -ge 2 ] || { echo "install.sh: --prefix needs a value" >&2; exit 2; }
      prefix=$2
      shift 2
      ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$prefix"
ln -sf "$here/bin/orchestra" "$prefix/orchestra"
echo "linked $prefix/orchestra -> $here/bin/orchestra"

case ":$PATH:" in
  *":$prefix:"*) ;;
  *)
    echo "note: $prefix is not on PATH. Add this to ~/.zshrc:"
    echo "  export PATH=\"$prefix:\$PATH\""
    ;;
esac

missing=""
for c in git jq tmux check-jsonschema claude; do
  command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
[ -z "$missing" ] || echo "missing dependencies:$missing"
