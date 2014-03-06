#!/bin/bash


ssh user@server /Users/user/postprocess.sh ${1}
exit



####################

parallel=4
dir=$1
outDir=${1}scantailor-out


# Create an output dir
mkdir $outDir


inotifywait -m -e close_write $dir | while read line
do
	name=$(echo $line | cut -d " " -f 3)
	currentNum=$(pgrep scantailor-cli | wc -l)

	echo "Queuing new file: $name"
	echo "Currently running Scantailor instances: $currentNum"

	while [ $currentNum -ge $parallel ]
	do
		sleep 1
		currentNum=$(pgrep scantailor-cli | wc -l)
	done

	echo "Launching Scantailor for file: $name ($(date))"

	scantailor-cli --color-mode=mixed "$dir/$name" "$outDir" &
done

