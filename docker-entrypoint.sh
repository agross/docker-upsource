#!/bin/bash

set -e

if [ "$1" = 'upsource' ]; then
  shift
  exec ./bin/upsource.sh "$@"
fi

exec "$@"
