#!/bin/bash
set -e
source $(dirname "$0")/build

i=test/doctest.coffee ; o=test/doctest.js
[ $i -nt $o ] && echo "Compiling $i" && coffee -b -c $i

echo 'Running doctests'
node test/doctest.js
