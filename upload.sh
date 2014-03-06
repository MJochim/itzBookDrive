#!/bin/sh

echo "cd "scantailor-in/$1"
put \"$2\"
put \"$3\"" | sftp -b - user@server 

