#!/bin/bash

ssh user@tailor-server /Users/user/postprocessing-scantailor.sh ${1} &
ssh user@ocr-server /home/user/postprocessing-ocr.sh ${1}

