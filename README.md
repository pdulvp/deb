# deb

Debian package repository for pdulvp's projects, served as a static APT
repository by GitHub Pages at:

    https://pdulvp.github.io/deb

The packages themselves are built by each project (see `prel release`) and
published here with `scripts/publish-deb.sh`; GitHub releases stay the place
where release notes and Windows builds live.

## Install a package

```sh
sudo curl -fsSL https://pdulvp.github.io/deb/pdulvp-deb-repo-key.asc \
    -o /usr/share/keyrings/pdulvp-deb-repo.asc
sudo gpg --dearmor < /usr/share/keyrings/pdulvp-deb-repo.asc \
    > /usr/share/keyrings/pdulvp-deb-repo.gpg
sudo rm /usr/share/keyrings/pdulvp-deb-repo.asc
echo "deb [signed-by=/usr/share/keyrings/pdulvp-deb-repo.gpg] https://pdulvp.github.io/deb stable main" \
    | sudo tee /etc/apt/sources.list.d/pdulvp.list
sudo apt update
sudo apt install pdcartes-tarot
```

## Publish a package

Prerequisites on the publishing machine: `dpkg-scanpackages` (dpkg-dev),
`apt-ftparchive` (apt-utils), `gpg`, `gh` (logged in), and the signing key
created once with:

```sh
scripts/make-signing-key.sh
```

Then, after a project's `prel release`:

```sh
# from local build artifacts:
scripts/publish-deb.sh build/pdcartes-tarot_1.1.2_amd64.deb --push

# or straight from an existing GitHub release:
scripts/publish-deb.sh --from-release pdulvp/pdcartes-tarot v1.1.2 --push

# regenerate and re-sign the indices without adding a package:
scripts/publish-deb.sh --reindex
```

Each run copies the .debs into `pool/`, rebuilds `dists/stable` and commits.
GitHub Pages redeploys on push, so the repository is live a minute later.

## Layout

```
├── pool/main/<pkg[0]>/<pkg>/<pkg>_<version>_<arch>.deb   the packages
├── dists/stable/
│   ├── main/binary-<arch>/Packages{,.gz}                  per-arch indices
│   ├── Release                                            checksums of the indices
│   ├── Release.gpg                                        detached signature
│   └── InRelease                                          clearsigned Release
├── pdulvp-deb-repo-key.asc                                public signing key
├── signing-key.txt                                        key id used by the scripts
└── scripts/
    ├── make-signing-key.sh
    └── publish-deb.sh
```

The suite is `stable` and the component is `main`; override the suite with
`DEB_REPO_SUITE` and the signing key with `DEB_REPO_KEY_ID`.
