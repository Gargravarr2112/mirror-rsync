#!/bin/bash
set -euo pipefail;

#A considerably simpler take on apt-mirror - parses the Packages files like apt-mirror, but then builds a file of .debs to download, which is then passed to rsync which does the rest.
#Saves the overhead of downloading each file over HTTP and considerably simpler to debug. Can now be configured using a file containing paths instead of running rsync many times in a loop.
#Just like apt-mirror, capable of running on only one Ubuntu release to save space.
#Author: Rob Johnson
#Date: 2017-09-20

syncDate=$(date +%F);
#File to build a list of files to rsync from the remote mirror - will contain one line for every file in the dists/ to sync
filename=packages-$syncDate.txt;
#Assumes a 'master source' file in /etc/mirror-rsync.d named for the masterSource value below. The file contains newline-separated
#entries of which dists/ to sync. See example in other file here.
masterSource='gb.archive.ubuntu.com';
#Adapt as necessary to your package mirror setup
localPackageStore="/srv/apt-mirror/$masterSource/ubuntu";

if [ ! -f /etc/mirror-rsync.d/$masterSource ]; then
    echo "No master source file found at /etc/mirror-rsync.d/$masterSource, create one and add one line per dists/ entry to sync";
    exit 1;
fi

#Add a marker for a second APT mirror to look for - if the sync falls on its face, can drop this out of the pair and sync exclusively from the mirror until fixed
if [ -f /mnt/packagemirror/lastSuccess ]; then
	rm -v /mnt/packagemirror/lastSuccess;
fi

echo "$syncDate $(date +%T) Starting, exporting to /tmp/$filename";

#In case leftover from testing or failed previous run
if [[ -f /tmp/$filename ]]; then
	rm -v "/tmp/$filename";
fi

echo "$(date +%T) Syncing releases";
rsync --no-motd --delete-during --archive --recursive --human-readable --files-from="/etc/mirror-rsync.d/$masterSource" $masterSource::ubuntu/dists "$localPackageStore/dists";

echo "$(date +%T) Generating package list";
#rather than hard-coding, use a config file to run the loop. The same config file as used above to sync the releases
while read release; do
	for repo in 'main' 'restricted' 'universe' 'multiverse'; do #Adapt if necessary
		for arch in 'amd64' 'i386'; do #Adapt if necessary
			if [[ ! -f $localPackageStore/dists/$release/$repo/binary-$arch/Packages ]]; then #uncompressed file not found
				echo "$(date +%T) Extracking $release $repo $arch Packages file from archive";
				gunzip --keep "$localPackageStore/dists/$release/$repo/binary-$arch/Packages.gz";
			fi
			echo "$(date +%T) Extracting packages from $release $repo $arch";
			if [[ -s $localPackageStore/dists/$release/$repo/binary-$arch/Packages ]]; then
				grep 'Filename: ' "$localPackageStore/dists/$release/$repo/binary-$arch/Packages" | sed 's/Filename: //' >> "/tmp/$filename";
			else
				echo "$(date +%T) Package list is empty, skipping";
			fi
		done
	done
done </etc/mirror-rsync.d/$masterSource

echo "$(date +%T) Deduplicating";

sort --unique "/tmp/$filename" > "/tmp/$filename.sorted";
rm -v "/tmp/$filename";
mv -v "/tmp/$filename.sorted" "/tmp/$filename";

echo "$(wc -l /tmp/$filename | awk '{print $1}') files to be sync'd";

echo "$(date +%T) Running rsync";

#rsync may error out due to excessive load on the source server, so try up to 3 times
set +e;
attempt=1;
exitCode=1;

while [[ $exitCode -gt 0 ]] && [[ $attempt -lt 4 ]];
do
	SECONDS=0;
	rsync --copy-links --files-from="/tmp/$filename" --no-motd --delete-during --archive --recursive --human-readable $masterSource::ubuntu "$localPackageStore/" 2>&1;
	exitCode=$?;
	if [[ $exitCode -gt 0 ]]; then
		waitTime=$((attempt*300)); #increasing wait time - 5, 10 and 15 minutes between attempts
		echo "rsync attempt $attempt failed with exit code $exitCode, waiting $waitTime seconds to retry";
		sleep $waitTime;
		let attempt+=1;
	fi
done

set -e;

#Exiting here will stop the lastSuccess file being created, and will stop APT02 running its own sync
if [[ $exitCode -gt 0 ]]; then
	echo "rsync failed all 3 attempts, erroring out";
	exit 2;
fi

echo "$(date +%T) Sync complete, runtime: $SECONDS s";

echo "$(date +%T) Deleting obsolete packages";

#Build a list of files that have been synced and delete any that are not in the list
find "$localPackageStore/pool/" -type f | { grep -Fvf "/tmp/$filename" || true; } | xargs --no-run-if-empty -I {} rm -v {}; # '|| true' used here to prevent grep causing pipefail if there are no packages to delete - grep normally returns 1 if no files are found

echo "$(date +%T) Complete";

rm -v "/tmp/$filename";

touch /mnt/packagemirror/lastSuccess;
