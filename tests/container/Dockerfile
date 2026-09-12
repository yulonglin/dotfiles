# Clean Ubuntu for an end-to-end install.sh + deploy.sh run.
#
# What this image deliberately is: the machine state install.sh assumes and
# nothing more — a stock ubuntu:24.04 with only what a human would already have
# before cloning the repo (git to clone it, zsh because both scripts are zsh,
# sudo and curl because a fresh Ubuntu has neither guaranteed for a non-root
# user). Every package install.sh performs is left to install.sh.
#
# What it is not: a Mac, a machine with credentials, or a machine with a
# display. See tests/container/README.md for the coverage boundary.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git sudo zsh locales tzdata \
    && rm -rf /var/lib/apt/lists/*

# install.sh runs `sudo apt` and must never be run as root itself (Homebrew's
# rule on macOS, and create_dev_user's assumption on Linux). NOPASSWD because
# the test is unattended by construction: a password prompt here is the stall
# this whole suite exists to catch, and it would be caught as a timeout.
RUN useradd --create-home --shell /bin/bash tester \
    && printf 'tester ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/90-tester \
    && chmod 0440 /etc/sudoers.d/90-tester

USER tester
WORKDIR /home/tester

# The repo arrives as `git archive HEAD`, so the image carries the committed
# tree and never the working copy. It is re-inited as a real, non-worktree git
# repo: the git-hooks component writes into .git/hooks, and guard_not_worktree
# must see a main checkout so no --allow-worktree flag is needed (passing one
# would mask a regression in the guard).
COPY --chown=tester:tester repo.tar /tmp/repo.tar
RUN mkdir -p /home/tester/dotfiles \
    && tar -xf /tmp/repo.tar -C /home/tester/dotfiles \
    && rm /tmp/repo.tar \
    && cd /home/tester/dotfiles \
    && git init -q -b main \
    && git config user.email tester@example.invalid \
    && git config user.name tester \
    && git add . \
    && git commit -q -m "container fixture"

ENTRYPOINT ["/bin/bash", "/home/tester/dotfiles/tests/container/contract.sh"]
