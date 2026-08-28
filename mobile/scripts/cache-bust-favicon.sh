#!/usr/bin/env bash
set -euo pipefail

web_dir="${1:-../priv/web}"
favicon_hash="$(shasum -a 256 "$web_dir/favicon.ico" | cut -c1-12)"

perl -0pi -e "s|href=\"/favicon\.ico(?:\?v=[^\"]*)?\"|href=\"/favicon.ico?v=$favicon_hash\"|g" \
  "$web_dir/index.html"
