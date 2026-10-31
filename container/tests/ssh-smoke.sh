#!/bin/bash
# Fast CI gate; owns only its uniquely named container and two empty volumes.
set -euo pipefail
image=${1:?Usage: ssh-smoke.sh IMAGE}
name="l4d2-bootstrap-test-$$-$RANDOM"
work=$(mktemp -d)
cleanup() {
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker volume rm "${name}-data" "${name}-ssh" >/dev/null 2>&1 || true
    rm -rf -- "$work"
}
trap cleanup EXIT
ssh-keygen -q -t ed25519 -N '' -f "$work/key"
docker run -d --init --name "$name" -p 127.0.0.1::4261 -e SSH_PORT=4261 \
    -v "${name}-data:/data" -v "${name}-ssh:/var/lib/l4d2/ssh" \
    "$image" /bin/sleep infinity >/dev/null
for ((i=0;i<60;i++)); do
    docker exec "$name" test -f /run/l4d2/sshd_config >/dev/null 2>&1 && break
    sleep 0.5
done
docker exec "$name" test ! -e /etc/sudoers.d/linuxgsm
docker exec -u linuxgsm "$name" mkdir -p /data/.ssh
docker exec -i -u linuxgsm "$name" sh -c 'chmod 700 /data/.ssh; umask 077; cat > /data/.ssh/authorized_keys' < "$work/key.pub"
port=$(docker port "$name" 4261/tcp | awk -F: '{print $NF}')
opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=5 -i "$work/key")
result=$(ssh "${opts[@]}" -p "$port" linuxgsm@127.0.0.1 'id -u; grep NoNewPrivs /proc/self/status')
[[ "$result" == $'1000\nNoNewPrivs:\t1' ]]
printf 'SSH/SFTP volume smoke\n' > "$work/input"
printf 'put %s /data/sftp-test\nget /data/sftp-test %s\nrm /data/sftp-test\n' "$work/input" "$work/output" > "$work/batch"
sftp "${opts[@]}" -P "$port" -b "$work/batch" linuxgsm@127.0.0.1 >/dev/null
cmp "$work/input" "$work/output"
echo 'Bootstrap image SSH key login, SFTP, session NNP and sudo policy: PASS'
