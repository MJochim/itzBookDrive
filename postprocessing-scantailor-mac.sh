#!/bin/bash

parallel=8

project="$SSH_ORIGINAL_COMMAND"

storageOut="storage/${project}/"
outDir="scantailor-out/${project}"
inDir="scantailor-in/${project}"

# Create an output dir
mkdir "$storageOut"
mkdir "$outDir"
mkdir "$inDir"

PATH=$PATH:/usr/local/bin:/opt/local/bin

fsw -r -x ${inDir} | while read line
do
	name=$(echo $line | grep Updated | cut -d " " -f 1)
	[ -z "$name" ] && continue
	currentNum=$(pgrep scantailor-cli | wc -l)

	echo "Queuing new file: $name"
	echo "Currently running Scantailor instances: $currentNum"

	while [ $currentNum -ge $parallel ]
	do
		sleep 1
		currentNum=$(pgrep scantailor-cli | wc -l)
	done

	echo "Launching Scantailor for file: $name ($(date))"

	(scantailor-cli --color-mode=mixed "$name" "$outDir"; cp "$outDir/$name.tif" "$outDir/$name" "$storageOut") &
done

