# mirror-rsync
A simple APT archive mirroring script using rsync, configurable to specific releases

## Requirements
The only significant requirement is `rsync`. Standard *nix tools cover all the rest.

## Installing
- Clone this repository to a folder
- Create a folder `/etc/mirror-rsync.d`
- Create a file in that folder named for the URL of your desired rsync mirror, containing your desired releases (see example)
- Edit the `mirror-rsync.sh` script and specify your rsync mirror/config file (above step) and your desired location on disk to store the repository
- Run `./mirror-rsync.sh` either manually or via `cron`.

## Rationale
I've previously tried `apt-mirror` and `debmirror` with varying degrees of success; with Ubuntu, I had regular problems with `apt-mirror` creating the `dep11` folder trees. With `debmirror` and HTTP, the process is quite slow due to each file being its own HTTP request. `rsync` is designed for this purpose and is much faster, but has the unwanted side effect with APT that it has to download the entire remote repository - this may include releases you don't use and don't have the space for. This script will download only the releases you want, quickly and efficiently.

## Enhancements
This was written while I worked for a startup and is more than a little hacky. Things that should be configurable (e.g. sources, architectures, branches) are hard-coded. I intend to add a proper configuration file now that I'm actually using it personally.

## License
For now, consider it licensed under the WTFPL - you can do whatever you like with this script. No warranty is included or implied. It should do what you expect, but the author is not responsible for loss of data, excessive usage bills, WWIII or any other issues that may arise from use (proper or improper) of this script.