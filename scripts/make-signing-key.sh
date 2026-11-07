#!/usr/bin/env bash
# make-signing-key.sh - Create the GPG key that signs this APT repository
#
# Usage: scripts/make-signing-key.sh [uid]
#
# Generates a dedicated RSA-4096 signing key in the local GPG keyring, writes
# its key id to signing-key.txt (what scripts/publish-deb.sh reads) and exports
# the public key as pdulvp-deb-repo-key.asc, the file users fetch to verify the
# repository. Run once per machine that publishes. Back up the private key:
# anyone who can read ~/.gnupg can sign packages as you.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

UID_ARG="${1:-pdulvp APT repository <pdulvp@laposte.net>}"

key_id_of_file() {
	[ -f signing-key.txt ] && tr -d '[:space:]' < signing-key.txt || true
}

if [ -n "$(key_id_of_file)" ] \
	&& gpg --list-secret-keys "$(key_id_of_file)" >/dev/null 2>&1; then
	echo "Signing key $(key_id_of_file) already in the keyring; nothing to do."
	exit 0
fi

gpg --batch --passphrase '' --quick-gen-key "$UID_ARG" rsa4096 sign never

KEY_ID=$(gpg --list-secret-keys --with-colons --with-fingerprint \
	| awk -F: '/^fpr/ { print $10; exit }')

printf '%s\n' "$KEY_ID" > signing-key.txt
gpg --batch --yes --armor --export "$KEY_ID" > pdulvp-deb-repo-key.asc

echo "Created signing key $KEY_ID"
echo "  key id:     signing-key.txt"
echo "  public key: pdulvp-deb-repo-key.asc (commit this)"
echo "Back up the private key now: gpg --armor --export-secret-keys $KEY_ID"
