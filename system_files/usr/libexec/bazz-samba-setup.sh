#!/bin/bash
# One-shot: set up the Samba audio drop share on first boot. Auth is NOT set
# here (no secrets in the image): the owner runs `sudo smbpasswd -a
# shrinksenpai` once after install.
set -euo pipefail

stamp=/var/lib/bazz-emu-inf/samba-audio-setup
[ -f "$stamp" ] && exit 0
mkdir -p "$(dirname "$stamp")"

install -d -m 0775 -o shrinksenpai -g shrinksenpai /srv/audio /srv/audio/in /srv/audio/out /srv/audio/done

# SELinux: without samba_share_t, smbd is denied on /srv/audio and the share
# fails silently for clients.
if command -v semanage >/dev/null; then
    semanage fcontext -a -t samba_share_t "/srv/audio(/.*)?" 2>/dev/null || \
        semanage fcontext -m -t samba_share_t "/srv/audio(/.*)?"
    restorecon -R /srv/audio
fi

# Port 445 is below Bazzite's open 1025-65535 game range, so samba needs the
# explicit service rule.
firewall-cmd --permanent --add-service=samba
firewall-cmd --reload

touch "$stamp"
