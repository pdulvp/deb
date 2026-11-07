#!/usr/bin/env bash
# publish-deb.sh - Add .deb packages to this APT repository and refresh the signed indices
#
# Usage:
#   scripts/publish-deb.sh <file.deb> [...]        Publish local .deb files
#   scripts/publish-deb.sh --from-release owner/repo [tag] [--asset <glob>]
#                                                  Download the .debs of a GitHub release, then publish them
#   scripts/publish-deb.sh --reindex               Regenerate and sign the indices only
#
# Options:
#   --asset <glob>   Release asset glob for --from-release (default '*.deb')
#   -m <message>     Commit message
#   --no-commit      Leave the changes uncommitted
#   --push           Push the current branch after committing
#   usage            Show this help
#
# Layout produced (suite 'stable', component 'main', overridable with
# DEB_REPO_SUITE):
#
#   pool/main/<pkg[0]>/<pkg>/<pkg>_<version>_<arch>.deb
#   dists/stable/main/binary-<arch>/Packages{,.gz}
#   dists/stable/Release, Release.gpg, InRelease
#
# Signing key id is read from $DEB_REPO_KEY_ID, else signing-key.txt (written
# by scripts/make-signing-key.sh).

set -euo pipefail

# The apt/dpkg tools must link against the system libraries; an inherited
# LD_LIBRARY_PATH (an editor's bundled runtime, say) breaks them with
# GLIBCXX version errors.
unset LD_LIBRARY_PATH LD_PRELOAD

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SUITE="${DEB_REPO_SUITE:-stable}"
COMPONENT="main"

usage() {
	sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

signing_key() {
	if [ -n "${DEB_REPO_KEY_ID:-}" ]; then
		printf '%s\n' "$DEB_REPO_KEY_ID"
	elif [ -f signing-key.txt ]; then
		tr -d '[:space:]' < signing-key.txt
	else
		echo "Error: no signing key - run scripts/make-signing-key.sh or set DEB_REPO_KEY_ID" >&2
		return 1
	fi
}

# add_deb <file.deb> - copy one package into pool/, print '<pkg> <version>'
add_deb() {
	local f="$1" pkg ver arch dest
	pkg=$(dpkg-deb -f "$f" Package)
	ver=$(dpkg-deb -f "$f" Version)
	arch=$(dpkg-deb -f "$f" Architecture)
	dest="pool/$COMPONENT/${pkg:0:1}/$pkg"
	mkdir -p "$dest"
	if [ -f "$dest/$(basename "$f")" ] \
		&& cmp -s "$f" "$dest/$(basename "$f")"; then
		echo "Already present: $pkg $ver ($arch)" >&2
	else
		cp "$f" "$dest/"
		echo "Added: $pkg $ver ($arch) -> $dest/$(basename "$f")" >&2
	fi
	printf '%s %s\n' "$pkg" "$ver"
}

# reindex - regenerate Packages, Release and the signatures
reindex() {
	local key arches arch dir tmp all_packages
	key=$(signing_key)

	shopt -s nullglob
	local debs=(pool/$COMPONENT/*/*/*.deb)
	if [ ${#debs[@]} -eq 0 ]; then
		echo "Error: no .deb under pool/$COMPONENT, nothing to index" >&2
		return 1
	fi

	# Architecture 'all' gets no index of its own: all-arch packages are
	# listed in every binary-<arch> index below. Only if the pool holds
	# nothing but all-arch packages does binary-all exist.
	arches=$(printf '%s\n' "${debs[@]}" \
		| while IFS= read -r f; do dpkg-deb -f "$f" Architecture; done \
		| sort -u | grep -v '^all$' | tr '\n' ' ' || true)
	arches="${arches% }"
	if [ -z "$arches" ]; then
		arches="all"
	fi

	# One stanza-filtered Packages per architecture; 'all' packages go in each.
	tmp=$(mktemp)
	dpkg-scanpackages --multiversion "pool/$COMPONENT" > "$tmp" 2>/dev/null

	for arch in $arches; do
		dir="dists/$SUITE/$COMPONENT/binary-$arch"
		mkdir -p "$dir"
		awk -v arch="$arch" '
			BEGIN { RS = ""; FS = "\n" }
			{
				for (i = 1; i <= NF; i++)
					if ($i ~ /^Architecture: /) { a = substr($i, 15); break }
				if (a == arch || a == "all") print $0 "\n"
			}
		' "$tmp" > "$dir/Packages"
		gzip -9c "$dir/Packages" > "$dir/Packages.gz"
	done
	rm -f "$tmp"

	# Drop index dirs of architectures no longer in the pool.
	for dir in dists/$SUITE/$COMPONENT/binary-*; do
		[ -d "$dir" ] || continue
		arch="${dir##*/binary-}"
		case " $arches " in *" $arch "*) ;; *) rm -rf "$dir" ;; esac
	done

	rm -f "dists/$SUITE/Release" "dists/$SUITE/Release.gpg" "dists/$SUITE/InRelease"
	apt-ftparchive \
		-o "APT::FTPArchive::Release::Origin=pdulvp" \
		-o "APT::FTPArchive::Release::Label=pdulvp" \
		-o "APT::FTPArchive::Release::Suite=$SUITE" \
		-o "APT::FTPArchive::Release::Codename=$SUITE" \
		-o "APT::FTPArchive::Release::Components=$COMPONENT" \
		-o "APT::FTPArchive::Release::Architectures=$arches" \
		-o "APT::FTPArchive::Release::Description=pdulvp Debian package repository" \
		release "dists/$SUITE" > "Release.tmp"
	mv "Release.tmp" "dists/$SUITE/Release"

	gpg --batch --yes --pinentry-mode loopback --local-user "$key" \
		--clearsign --output "dists/$SUITE/InRelease" "dists/$SUITE/Release"
	gpg --batch --yes --pinentry-mode loopback --local-user "$key" \
		--armor --detach-sign --output "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"

	echo "Reindexed dists/$SUITE ($COMPONENT: $arches) and signed as $key"
}

commit_changes() {
	local message="$1"
	git add -- pool dists signing-key.txt pdulvp-deb-repo-key.asc 2>/dev/null || git add -- pool dists
	if git diff --cached --quiet; then
		echo "Nothing to commit."
		return 0
	fi
	git commit --quiet -m "$message"
	echo "Committed: $message"
}

main() {
	local debs=() from_release="" tag="" asset='*.deb' message="" commit=1 push=0 reindex_only=0

	while [ $# -gt 0 ]; do
		case "$1" in
			usage|-h|--help) usage; return 0 ;;
			--from-release) from_release="$2"; shift 2 ;;
			--asset) asset="$2"; shift 2 ;;
			--reindex) reindex_only=1; shift ;;
			-m|--message) message="$2"; shift 2 ;;
			--no-commit) commit=0; shift ;;
			--push) push=1; shift ;;
			*.deb) debs+=("$1"); shift ;;
			*)
				if [ -n "$from_release" ] && [ -z "$tag" ]; then
					tag="$1"; shift
				else
					echo "Error: unknown argument '$1'" >&2; usage >&2; return 1
				fi
				;;
		esac
	done

	if [ -n "$from_release" ]; then
		local tmp
		tmp=$(mktemp -d)
		if [ -n "$tag" ]; then
			gh release download "$tag" --repo "$from_release" --pattern "$asset" --dir "$tmp"
		else
			gh release download latest --repo "$from_release" --pattern "$asset" --dir "$tmp"
			tag=$(gh release view latest --repo "$from_release" --json tagName --jq .tagName)
		fi
		echo "Downloaded $asset from $from_release $tag"
		local f
		for f in "$tmp"/*.deb; do debs+=("$f"); done
	fi

	if [ ${#debs[@]} -eq 0 ] && [ -z "${1:-}" ]; then :; fi

	local published=""
	if [ ${#debs[@]} -gt 0 ]; then
		shopt -s nullglob
		local f
		for f in "${debs[@]}"; do
			[ -f "$f" ] || { echo "Error: no such file '$f'" >&2; return 1; }
			published+="$(add_deb "$f")"$'\n'
		done
	fi

	reindex

	if [ "$commit" = "1" ]; then
		if [ -z "$message" ]; then
			if [ -n "$published" ]; then
				message="Publish to $SUITE: $(printf '%s' "$published" | paste -sd, -)"
			else
				message="Reindex $SUITE"
			fi
		fi
		commit_changes "$message"
	fi

	if [ "$push" = "1" ]; then
		git push origin HEAD
		echo "Pushed $(git rev-parse --abbrev-ref HEAD)"
	fi
}

main "$@"
