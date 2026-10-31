# Source only in unprivileged operational sessions; values are shell-quoted data.
if [ -r /run/l4d2/environment.json ]; then
    eval "$(/usr/bin/python3 -I /usr/local/libexec/l4d2/environment.py --exports)"
fi
