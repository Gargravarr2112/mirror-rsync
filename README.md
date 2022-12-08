# mirror-rsync
A simple APT archive mirroring script using rsync, configurable to specific releases

## Requirements
The only significant requirement is `rsync`. Standard *nix tools cover all the rest:
- `awk`
- `sed`
- `gunzip`
Everything else is pure `bash`.

## Installing
- Clone this repository to a folder
- Create a folder `/etc/mirror-rsync.d`
- Create one or more files in that folder named for the URL of your desired rsync mirror, containing the following lines in bash syntax (no spaces, see example):
-- `name=string` the name of the APT repository (e.g. `ubuntu`)
-- `releases=(array)` the releases under `dists/` to sync packages from (e.g. `jammy jammy-updates jammy-backports`)
-- `repositories=(array)` the repositories under each release to sync from (e.g. `main restricted universe`)
-- `architectures=(array)` the CPU architectures to use (e.g. `i386 amd64`)
- Edit the `mirror-rsync.sh` script and edit the top lines to specify your desired location on disk to store the repository (and if necessary, the location of the `mirror-rsync.d` folder if `/etc/` is not suitable)
- Run `./mirror-rsync.sh` without arguments either manually or via `cron`.

## Rationale
I've previously tried `apt-mirror` and `debmirror` with varying degrees of success; with Ubuntu, I had regular problems with `apt-mirror` creating the `dep11` folder trees. With `debmirror` and HTTP, the process is quite slow due to each file being its own HTTP request. `rsync` is designed for this purpose and is much faster, but has the unwanted side effect with APT that it has to download the entire remote repository - this may include releases you don't use and don't have the space for. This script will download only the releases you want, quickly and efficiently.

## Enhancements
This was written while I worked for a startup and is more than a little hacky. Things that should be configurable (e.g. sources, architectures, branches) weren't at the time. I have now rewritten it to support syncing from multiple repositories and specifying the actual contents of the remote repositories to get.

## License
For now, consider it licensed under the WTFPL - you can do whatever you like with this script. No warranty is included or implied. It should do what you expect, but the author is not responsible for loss of data, excessive usage bills, WWIII or any other issues that may arise from use (proper or improper) of this script.