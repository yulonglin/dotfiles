# SSH servers accept keys only

Every machine this repo deploys runs its ssh server with password and keyboard-interactive logins switched off. `deploy.sh` enforces it through the `sshd-key-only` component, which is on by default (`--no-sshd-key-only` skips it).

## Why both settings, and why a drop-in

A server that accepts passwords is one `passwd` away from being guessable. On 2026-11-03 a cloud server took about 12,000 password guesses a day, and the only thing stopping them was that no account happened to have a usable password. The Mac offered passwords to anyone on the same Wi-Fi.

`config/sshd/01-key-only.conf` sets `PasswordAuthentication no` and `KbdInteractiveAuthentication no`. Both lines are needed. On macOS a password arrives as keyboard-interactive through PAM, so turning off `PasswordAuthentication` alone still lets one in.

sshd keeps the first value it reads for each keyword, and drop-ins in `/etc/ssh/sshd_config.d/` load in name order. The `01-` prefix puts this file ahead of distro files such as Ubuntu's `50-cloud-init.conf` (which sometimes turns passwords back on) and macOS's `100-macos.conf`.

## Commands

```
ssh-key-only check            # this machine: exit 0 keys only, 1 passwords offered, 3 no server
ssh-key-only check hn         # any host in ~/.ssh/config
sudo ~/code/dotfiles/custom_bins/ssh-key-only install   # install, validate, reload, re-check
ssh-key-only install --dry-run   # run the lockout guard only
```

`check` needs no privilege. It connects with every client login method switched off, so the server replies with the list of methods it would accept and nothing is tried. That makes it the ground truth: a drop-in that another file overrides still shows up as a failure.

`install` refuses when the login user's `~/.ssh/authorized_keys` holds no public key, since key-only ssh would lock that user out. It validates with `sshd -t`, removes the file again if validation fails, and fails if `sshd -T` shows another file still winning. On Linux it reloads `ssh.service` or `sshd.service`, or sends SIGHUP to the listener where there is no systemd (RunPod). On macOS nothing needs reloading: launchd starts a fresh `sshd -i` per connection, which reads the config anew.

Under `sudo`, macOS's `secure_path` drops `custom_bins/`, so give the full path: `sudo ~/code/dotfiles/custom_bins/ssh-key-only install`.

## How deploy behaves

`deploy.sh` runs `check` first. A machine that is already key-only, or that runs no ssh server, never prompts for sudo. Otherwise it installs when sudo is cached or when it runs as root, and when neither applies it prints the `sudo … install` line to run.

## Undo

```
sudo rm /etc/ssh/sshd_config.d/01-key-only.conf
```

On Linux, follow it with `sudo systemctl reload ssh`.
