#!/bin/bash
# SSH is configured and supervised by the protected bootstrap API v2.
# This compatibility slot deliberately performs no privileged runtime operation.
test -f /run/l4d2/sshd_config
