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
args: "-rt --size-only --modify-window=2 --exclude thumbs --exclude encoded-video"
```

## Option reference

- `source`: source folder under `/share` or `/media`
- `destination`: destination folder under `/share` or `/media`
- `run_mode`: `once` or `interval`
- `schedule_minutes`: sync interval when `run_mode` is `interval`
- `args`: raw rsync arguments, for example `-a --delete --progress`

## Trailing slash behavior

If you set `source` or `destination` with a trailing `/`, the add-on preserves it
when executing `rsync`. This matters because rsync treats these forms differently.

## Examples

Copy media to backup:

```yaml
source: /share/media/
destination: /share/backup/media/
run_mode: once
schedule_minutes: 60
args: "-a --progress --verbose --human-readable --itemize-changes"
```

Mirror source to destination:

```yaml
source: /share/important/
destination: /share/backup/important/
run_mode: once
schedule_minutes: 60
args: "-a --delete --verbose --human-readable --itemize-changes"
```

Preview only:

```yaml
source: /share/documents/
destination: /share/backup/documents/
run_mode: once
schedule_minutes: 60
args: "-a --dry-run --progress --verbose --human-readable --itemize-changes"
```

Scheduled sync every 6 hours:

```yaml
source: /media/archive/
destination: /share/backup/archive/
run_mode: interval
schedule_minutes: 360
args: "-a --progress --verbose --human-readable --itemize-changes"
```

## Notes

- If your external disk is exposed inside Home Assistant under `/share`, this
  add-on can work with it.
- If your storage is exposed under `/media`, that works too.
- If the source path does not exist, the add-on stops with an error.
- The destination folder is created automatically if needed.
- In `interval` mode the add-on stays running and repeats the sync forever.
- The logs include the exact `rsync` command that was executed.
