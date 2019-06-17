#!/bin/bash

read -p "エンターキーを押下すると音声録音(10秒間)が始まります" rec
if [ -z $rec ]; then
 rec --channels=1 --bits=16 --rate=16000 ja-sample.flac trim 0 10
fi

