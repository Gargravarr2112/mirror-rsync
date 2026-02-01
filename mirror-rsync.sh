#!/bin/bash
set -euo pipefail;

#A considerably simpler take on apt-mirror - parses the Packages files like apt-mirror, but then builds a file of .debs to download, which is then passed to rsync which does the rest.
#Saves the overhead of downloading each file over HTTP and considerably simpler to debug. Can now be configured using a file containing paths instead of running rsync many times in a loop.
#Just like apt-mirror, capable of running on only one Ubuntu release to save space.
#Author: Rob Johnson
#Date: 2017-09-20

syncDate=$(date +%F);

#Adapt as necessary to your package mirror setup
sourceFolder='/etc/mirror-rsync.d';
baseDirectory="/srv/apt";

#Basic checks
if [[ ! -d "$sourceFolder" ]]; then
		echo "Source folder $sourceFolder does not exist!"
		exit 1;

elif [[ $(ls -1 "$sourceFolder"/* | wc -l) -eq 0 ]]; then
    echo "No master source file(s) found in $sourceFolder, create one and add name, releases, repositories and architectures per README." 1>&2;
    exit 1;
elif [[ ! $(which rsync) ]] || [[ ! $(which sed) ]] || [[ ! $(which awk) ]]; then
	echo "Missing one or more of required tools 'rsync', 'sed' and 'awk' (or they are not in the PATH for this user)." 1>&2;
	exit 1;
elif [[ ! $(which gunzip) ]] && [[ ! $(which xzcat) ]]; then
	echo "Warning: missing both 'gunzip' and 'xzcat', required to work with certain repositories that do not provide uncompressed Packages lists. This may not work with your chosen repository. Install gzip and/or xz for best compatibility." 1>&2;
fi

#Add a marker for a second APT mirror to look for - if the sync falls on its face, can drop this out of the pair and sync exclusively from the mirror until fixed
if [[ -f $baseDirectory/lastSuccess ]]; then
	rm -v "$baseDirectory/lastSuccess";
fi
for sourceServer in "$sourceFolder"/*
do
	source "$sourceServer";
	if [[ -z "$name" ]] || [[ -z "$releases" ]] || [[ -z "$repositories" ]] || [[ -z "$architectures" ]]
	then
		echo "Error: $sourceServer is missing one or more of 'name', 'releases', 'repositories' or 'architectures' entries! Skipping." 1>&2;
		continue;
	fi

	masterSource=$(basename "$sourceServer");
	#File to build a list of files to rsync from the remote mirror - will contain one line for every file in the dists/ to sync
	filename="packages-$masterSource-$syncDate.txt";

	echo "$syncDate $(date +%T) Starting, exporting to /tmp/$filename";

	#In case leftover from testing or failed previous run
	if [[ -f "/tmp/$filename" ]]; then
		rm -v "/tmp/$filename";
	fi

	echo "$(date +%T) Syncing releases";
	localPackageStore="$baseDirectory/$masterSource/$name";
	mkdir -p "$localPackageStore/dists"

	echo -n ${releases[*]} | sed 's/ /\n/g' | rsync --no-motd --delete-during --archive --recursive --human-readable --files-from=- $masterSource::"$name/dists/" "$localPackageStore/dists/";

	echo "$(date +%T) Generating package list";
	#rather than hard-coding, use a config file to run the loop. The same config file as used above to sync the releases
	for release in ${releases[*]}; do
		for repo in ${repositories[*]}; do
			for arch in ${architectures[*]}; do
				pathPackages="$localPackageStore/dists/$release/$repo/binary-$arch/Packages";
				if [[ ! -f "$pathPackages" ]]; then  #uncompressed file not found
					if [[ $(which gunzip) ]]; then #See issue #5 - some distros don't provide gunzip by default but have xz
					  if [[ -f "$pathPackages.gz" ]]; then
							packageArchive="$pathPackages.gz";
							echo "$(date +%T) Extracting $release $repo $arch Packages file from archive $packageArchive";
							if [[ -L "$packageArchive" ]]; then #Some distros (e.g. Debian) make Packages.gz a symlink to a hashed filename. NB. it is relative to the binary-$arch folder
								echo "$(date +%T) Archive is a symlink, resolving";
								packageArchive=$(readlink $packageArchive | sed --expression "s_^_${packageArchive}_" --expression 's/Packages\.gz//');
							fi
							gunzip <"$packageArchive" >"$pathPackages";
						fi
					elif [[ $(which xzcat) ]]; then
						if [[ -f "$pathPackages.xz" ]]; then
							packageArchive="$pathPackages.xz";
							echo "$(date +%T) Extracting $release $repo $arch Packages file from archive $packageArchive";
							if [[ -L "$packageArchive" ]]; then #Same as above
								echo "$(date +%T) Archive is a symlink, resolving";
								packageArchive=$(readlink $packageArchive | sed --expression "s_^_${packageArchive}_" --expression 's/Packages\.xz//');
							fi
							xzcat <"$packageArchive" >"$pathPackages";
						fi
					else
						echo "$(date +%T) Error: uncompressed package list not found in remote repo and decompression tools for .gz or .xz files not found on this system, aborting. Please install either gunzip or xzcat to use this script." 1>&2;
						exit 1;
					fi
				fi
				echo "$(date +%T) Extracting packages from $release $repo $arch";
				if [[ -s "$pathPackages" ]]; then #Have experienced zero filesizes for certain repos
					awk '/^Filename: / { print $2; }' "$pathPackages" >> "/tmp/$filename";
				else
					echo "$(date +%T) Package list is empty, skipping";
				fi
			done
		done
	done

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
		rsync --copy-links --files-from="/tmp/$filename" --no-motd --delete-during --archive --recursive --human-readable $masterSource::$name "$localPackageStore/" 2>&1;
		exitCode=$?;
		if [[ $exitCode -gt 0 ]]; then
			waitTime=$((attempt*300)); #increasing wait time - 5, 10 and 15 minutes between attempts
			echo "$(date +%T) rsync attempt $attempt failed with exit code $exitCode, waiting $waitTime seconds to retry" 1>&2;
			sleep $waitTime;
			let attempt+=1;
		fi
	done

	set -e;

	#Exiting here will stop the lastSuccess file being created, and will stop APT02 running its own sync
	if [[ $exitCode -gt 0 ]]; then
		echo "rsync failed all 3 attempts, erroring out" 1>&2;
		exit 2;
	fi

	echo "$(date +%T) Sync from $masterSource complete, runtime: $SECONDS s";

	echo "$(date +%T) Deleting obsolete packages";

	#Build a list of files that have been synced and delete any that are not in the list
	find "$localPackageStore/pool/" -type f | { grep -Fvf "/tmp/$filename" || true; } | xargs --no-run-if-empty -I {} rm -v {}; # '|| true' used here to prevent grep causing pipefail if there are no packages to delete - grep normally returns 1 if no files are found

	echo "$(date +%T) Completed $masterSource";

	rm -v "/tmp/$filename";
done
touch "$baseDirectory/lastSuccess";

echo "$(date +%T) Finished";
