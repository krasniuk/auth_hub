#! /bin/bash

appName=auth_hub

pathFile=$(realpath $0)
pathDir=$(dirname $pathFile)

cd $pathDir
cd ../../../../

rebar3 as prod release
cd _build/prod/rel/$appName/bin/
./$appName console
