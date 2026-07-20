#!/usr/bin/env bash
# Encrypt the admin kubeconfig to the three reviewers using a throwaway GPG keyring.
# Produces <kubeconfig>.gpg decryptable by ANY of the recipients.
#
# Usage: scripts/encrypt-kubeconfig.sh <kubeconfig> <recipient1.asc> <recipient2.asc> <recipient3.asc>
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <kubeconfig> <pubkey.asc> [<pubkey.asc> ...]" >&2
  exit 1
fi

KCFG="$1"; shift
[ -f "$KCFG" ] || { echo "no such file: $KCFG" >&2; exit 1; }

GNUPGHOME="$(mktemp -d)"; export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT
chmod 700 "$GNUPGHOME"

recipients=()
for key in "$@"; do
  fpr="$(gpg --with-colons --import-options show-only --import "$key" | awk -F: '/^fpr:/{print $10; exit}')"
  echo ">> importing $key  (fingerprint: $fpr)"
  gpg --import "$key"
  recipients+=(--recipient "$fpr")
done

echo ">> VERIFY these fingerprints out-of-band (WhatsApp) before sending:"
gpg --list-keys --with-fingerprint

gpg --trust-model always --armor "${recipients[@]}" --output "${KCFG}.gpg" --encrypt "$KCFG"

echo ">> wrote ${KCFG}.gpg — recipient key IDs:"
gpg --list-packets "${KCFG}.gpg" | awk '/pubkey enc packet/{f=1} f && /keyid/{print; f=0}'
echo ">> attach ONLY ${KCFG}.gpg. Do not commit the plaintext kubeconfig."
