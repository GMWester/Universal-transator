#!/usr/bin/env bash
# Downloads the open datasets used by tools/build_assets.py into data-src/.
set -euo pipefail
D="${1:-data-src}"
mkdir -p "$D" && cd "$D"
for r in cldf-datasets/wals grambank/grambank glottolog/glottolog-cldf; do
  n=$(basename "$r")
  [ -d "$n" ] || git clone --depth 1 "https://github.com/$r" "$n"
done
for p in cldr-localenames-full cldr-misc-full cldr-core; do
  ls -d "$p"-*/ >/dev/null 2>&1 && continue
  f=$(npm pack "$p" --silent | tail -1)
  d="${f%.tgz}"; mkdir -p "$d" && tar xzf "$f" -C "$d" && rm "$f"
done
pip install --quiet regex
echo "sources ready in $D; now run: python3 tools/build_assets.py --src $D --out assets/data"
