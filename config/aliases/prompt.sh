# aliases/prompt.sh — prompt-legend: say what each part of the p10k prompt means
#
# Lit rows are what your prompt shows right now (with the live value on the
# right); grey rows are the rest of the key. The git rows mirror the parts built
# by my_git_formatter in config/p10k.zsh — keep the two in step.

# _prompt_legend_row NOW KEY MEANING — lit with NOW when NOW is non-empty and non-zero.
_prompt_legend_row() {
  local now=$1 key=$2 meaning=$3
  if [[ -n $now && $now != 0 ]]; then
    print -rP -- "  %B${(r:18:)key}%b ${meaning}  %178F← ${now//\%/%%}%f"
  else
    print -rP -- "  %244F${(r:18:)key} ${meaning}%f"
  fi
}

prompt-legend() {
  local last=$?  # keep first: the exit status of the command before this one
  emulate -L zsh
  local row=_prompt_legend_row

  print -P -- "%BGit%b  %244F(colours: %76Fgreen%244F branch and sync · %178Fyellow%244F your uncommitted work · %39Fblue%244F new files · %196Fred%244F conflict · grey = still loading)%f"
  print -P -- "  %244F(below 100 columns the words drop and only the symbols show: main !1 ?3)%f"
  local in_repo=
  if [[ $VCS_STATUS_RESULT == ok-* && $PWD/ == ${VCS_STATUS_WORKDIR}/* ]]; then
    in_repo=1
    if (( $+functions[my_git_formatter] )); then
      # p10k leaves the last-drawn segment in this global; the formatter returns it if set.
      local P9K_CONTENT=
      my_git_formatter 1
      print -rP -- "  now: ${my_git_format}%f"
    fi
  else
    print -P -- "  %244Fnow: not in a git repo%f"
  fi
  local -i behind ahead pbehind pahead conflicted staged unstaged untracked
  if [[ -n $in_repo ]]; then
    behind=$VCS_STATUS_COMMITS_BEHIND ahead=$VCS_STATUS_COMMITS_AHEAD
    pbehind=$VCS_STATUS_PUSH_COMMITS_BEHIND pahead=$VCS_STATUS_PUSH_COMMITS_AHEAD
    conflicted=$VCS_STATUS_NUM_CONFLICTED staged=$VCS_STATUS_NUM_STAGED
    unstaged=$VCS_STATUS_NUM_UNSTAGED untracked=$VCS_STATUS_NUM_UNTRACKED
  fi
  $row "${in_repo:+$VCS_STATUS_LOCAL_BRANCH}" "<branch>"         "the branch you are on"
  $row $behind                "⇣N to pull"        "remote commits you lack, as of the last fetch (git pull)"
  $row $ahead                 "⇡N to push"        "your commits not on the remote yet (git push)"
  $row $(( pbehind + pahead )) "⇠N / ⇢N"           "the same, against a separate push remote (a fork)"
  $row $staged                "+N staged"         "files staged: they go into the next commit"
  $row $unstaged              "!N modified"       "tracked files changed but not staged (git add)"
  $row $untracked             "?N untracked"      "files git has never tracked: not staged, in no commit"
  $row $conflicted            "~N conflicts"      "files with merge conflicts to fix"
  $row "${in_repo:+$VCS_STATUS_ACTION}" "<op> in progress" "a merge, rebase or cherry-pick is not finished"
  local lines=
  [[ -n $in_repo && -n $_my_git_diffstat && $_my_git_diffstat_dir == ${VCS_STATUS_WORKDIR:A} ]] &&
    (( staged + unstaged )) && lines="+${_my_git_diffstat[(w)1]} −${_my_git_diffstat[(w)2]}"
  $row "$lines"               "+N −M lines"       "lines added/removed vs last commit, like GitHub (untracked not counted)"
  $row ""                     "wip"              "the last commit message says WIP"
  $row ""                     "─ unknown"         "repo too big to count changes"
  $row ""                     ":other-branch"     "the remote branch, when its name differs from yours"
  $row ""                     "#tag  @1a2b3c4d"   "shown instead of a branch when HEAD is detached"

  print -P -- "%BRight side%b"
  local duration=
  (( ${+P9K_COMMAND_DURATION_SECONDS} && P9K_COMMAND_DURATION_SECONDS >= 3 )) &&
    duration=$(printf '%.0fs' $P9K_COMMAND_DURATION_SECONDS)
  local env_name=${VIRTUAL_ENV:+${VIRTUAL_ENV:t} ($VIRTUAL_ENV)}
  [[ -z $env_name && -n $CONDA_DEFAULT_ENV ]] && env_name="conda: $CONDA_DEFAULT_ENV"
  $row "${${(M)last:#0}:+yes}" "✔"                 "the last command succeeded"
  $row "${last:#0}"           "✘ N"               "the last command failed with exit code N"
  $row "$duration"            $'\uF253'" 1m 2s"   "how long the last command ran (shown at 3s or more)"
  $row ${#jobstates}          $'\uF013'           "jobs running in the background of this shell"
  $row "${DIRENV_DIR:+loaded}" "▼"                "direnv loaded a .envrc for this directory"
  $row "$env_name"            $'\uE63C'" name"    "the active Python venv or conda env"
  $row ""                     "user@host"         "shown only over SSH or as root"
  $row ""                     "22:31:04"          "the time the prompt was drawn"
}
