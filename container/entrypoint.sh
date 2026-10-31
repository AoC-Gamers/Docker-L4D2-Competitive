#!/bin/sh
# Compatibility path. Privileged code lives outside the mutable runtime tree.
exec /usr/bin/python3 -I /usr/local/libexec/l4d2/bootstrap.py "$@"
