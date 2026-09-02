# Local Rsync

`Local Rsync` is a very small Home Assistant add-on that runs `rsync` between
two local folders.

It is designed for a setup where:

- an external disk is mounted somewhere under `/share`
- or files are available under `/media`
- you want to sync local data into another local folder such as `/share/backup`
- you do not want SSH, remote hosts, keys, or network configuration

## What it does

The add-on can either:

- run one `rsync` command and exit
- stay running and repeat the sync on a fixed interval

## Installation note

This add-on is currently set up for local building by Home Assistant during
installation. That is useful before publishing a release image to GHCR.

## Path restrictions

For safety, both `source` and `destination` must resolve under `/share` or `/media`.

Examples:

- `/share/camera`
- `/share/external_disk/documents`
- `/share/backup`
- `/media/photos`
- `/media/usb_backup`

## Configuration

```yaml
source: /share/source/
destination: /share/backup/
run_mode: once
schedule_minutes: 60
archive: true
delete: false
checksum: false
verbose: true
dry_run: false
extra_args: ""
```

## Option reference

- `source`: source folder under `/share` or `/media`
- `destination`: destination folder under `/share` or `/media`
- `run_mode`: `once` or `interval`
- `schedule_minutes`: sync interval when `run_mode` is `interval`
- `archive`: enables `-a`
- `delete`: enables `--delete`
- `checksum`: enables `--checksum`
- `verbose`: enables readable logging flags
- `dry_run`: enables `--dry-run`
- `extra_args`: extra raw `rsync` flags, for example `--progress`

## Examples

Copy media to backup:

```yaml
source: /share/media/
destination: /share/backup/media/
run_mode: once
schedule_minutes: 60
archive: true
delete: false
checksum: false
verbose: true
dry_run: false
extra_args: "--progress"
```

Mirror source to destination:

```yaml
source: /share/important/
destination: /share/backup/important/
run_mode: once
schedule_minutes: 60
archive: true
delete: true
checksum: false
verbose: true
dry_run: false
extra_args: ""
```

Preview only:

```yaml
source: /share/documents/
destination: /share/backup/documents/
run_mode: once
schedule_minutes: 60
archive: true
delete: false
checksum: false
verbose: true
dry_run: true
extra_args: "--progress"
```

Scheduled sync every 6 hours:

```yaml
source: /media/archive/
destination: /share/backup/archive/
run_mode: interval
schedule_minutes: 360
archive: true
delete: false
checksum: false
verbose: true
dry_run: false
extra_args: "--progress"
```

## Notes

- If your external disk is exposed inside Home Assistant under `/share`, this
  add-on can work with it.
- If your storage is exposed under `/media`, that works too.
- If the source path does not exist, the add-on stops with an error.
- The destination folder is created automatically if needed.
- In `interval` mode the add-on stays running and repeats the sync forever.
