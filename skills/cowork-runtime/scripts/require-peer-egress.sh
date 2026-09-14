#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Cowork peer launch blocked: %s\n' "$1" >&2
  exit 1
}

if [[ "${1-}" == --help ]]; then
  printf '%s\n' 'usage: require-peer-egress.sh <claude|codex|agy|copilot>'
  exit 0
fi

[[ $# -eq 1 && -n "$1" ]] || fail 'pass the peer destination.'
destination=$1
classification=${COWORK_DATA_CLASSIFICATION-}
approved=${COWORK_APPROVED_DESTINATIONS-}

case "$classification" in
  public|internal) ;;
  confidential|restricted) fail "classification '$classification' is not permitted for peer export." ;;
  *) fail 'set COWORK_DATA_CLASSIFICATION to public, internal, confidential, or restricted.' ;;
esac

case ",$approved," in
  *,"$destination",*) ;;
  *) fail "destination '$destination' is not listed in COWORK_APPROVED_DESTINATIONS." ;;
esac
