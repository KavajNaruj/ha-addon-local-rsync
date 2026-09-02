# Home Assistant Local Rsync Add-on

Simple Home Assistant add-on repository with one add-on for running `rsync`
between two local folders mounted inside Home Assistant.

Primary use case:

- mount an external disk into `/share`
- or use folders under `/media`
- keep syncing data to something like `/share/backup`
- avoid SSH, remote hosts, keys, and network setup
- optionally run the sync repeatedly on a schedule

## Repository contents

- `local_rsync/` - the actual Home Assistant add-on
- `repository.yaml` - metadata for adding this GitHub repository to Home Assistant

## Install from GitHub

1. Push this repository to GitHub.
2. In Home Assistant, open `Settings > Add-ons > Add-on Store`.
3. Open the repository dialog.
4. Add your GitHub repository URL.
5. Install the `Local Rsync` add-on.

## Local development

If you are testing directly on a Home Assistant machine, copy this repository into
the local add-ons folder and refresh the add-on store.

## GitHub Actions

This repository includes:

- `.github/workflows/ci.yml` for syntax checks and Docker build verification
- `.github/workflows/release.yml` for publishing multi-arch images to GHCR
- `local_rsync/icon.png` and `local_rsync/logo.png` for Home Assistant store branding

The release workflow is intended to publish `ghcr.io/kavajnaruj/local-rsync`
when a GitHub release is published.

For early testing in Home Assistant, the add-on is configured to build locally
on the Home Assistant host instead of pulling a prebuilt image.

## Notes

- This add-on is intentionally limited to local filesystem sync.
- Source and destination must resolve under `/share` or `/media`.
- Sync jobs are configured through a `jobs` array.
