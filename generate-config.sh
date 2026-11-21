#!/usr/bin/env bash
# Generates evilginx/config/config.json and evilginx/phishlets/am-phishlet.yaml from their
# .template counterparts, filling in the tenant/journey/phishing-domain values from settings.env.
# Run this every time you change settings.env - it always regenerates from the templates, so it's
# safe to run repeatedly.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f settings.env ]; then
  echo "settings.env not found. Copy settings.env.example to settings.env and fill in your" >&2
  echo "tenant's values first:" >&2
  echo "  cp settings.env.example settings.env" >&2
  exit 1
fi

# shellcheck disable=SC1091
source settings.env

required=(TARGET_SUB TARGET_DOMAIN REALM TREE_NAME PHISHING_DOMAIN)
missing=()
for v in "${required[@]}"; do
  if [ -z "${!v:-}" ]; then
    missing+=("$v")
  fi
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing required settings in settings.env: ${missing[*]}" >&2
  echo "(PHISH_SUB may legitimately be left blank - everything else is required.)" >&2
  exit 1
fi

PHISH_SUB="${PHISH_SUB:-}"

sed \
  -e "s|<target_sub>|${TARGET_SUB}|g" \
  -e "s|<target_domain>|${TARGET_DOMAIN}|g" \
  -e "s|<realm>|${REALM}|g" \
  -e "s|<tree_name>|${TREE_NAME}|g" \
  -e "s|<phishing_domain>|${PHISHING_DOMAIN}|g" \
  evilginx/config/config.json.template > evilginx/config/config.json

sed \
  -e "s|<target_sub>|${TARGET_SUB}|g" \
  -e "s|<target_domain>|${TARGET_DOMAIN}|g" \
  -e "s|<realm>|${REALM}|g" \
  -e "s|<tree_name>|${TREE_NAME}|g" \
  -e "s|<phish_sub>|${PHISH_SUB}|g" \
  evilginx/phishlets/am-phishlet.yaml.template > evilginx/phishlets/am-phishlet.yaml

echo "Generated evilginx/config/config.json and evilginx/phishlets/am-phishlet.yaml."
echo

if [ -n "$PHISH_SUB" ]; then
  phish_host="${PHISH_SUB}.${PHISHING_DOMAIN}"
else
  phish_host="${PHISHING_DOMAIN}"
fi

echo "Next steps, using your settings:"
echo
echo "  sudo -- sh -c -e \"echo '127.0.0.1 ${phish_host}' >> /etc/hosts\""
echo
echo "  cd evilginx && docker build -f Dockerfile -t aitm-am-demo:edge ."
echo "  tail -f /dev/null | docker run --rm -i -p 443:443 aitm-am-demo:edge"
echo
echo "  https://${phish_host}/YStcNrSR"
