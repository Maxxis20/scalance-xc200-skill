# config.sh - settings shared by the scripts; sourced, not run.
#
# Settings come from the environment or from the file <work folder>/config (plain NAME=value lines, shell syntax);
# the work folder is ~/.scalance (SW_HOME).
#   SW_HOST          the switch's address (required)
#   SW_USER          CLI user (default admin)
#   SW_SECRET        name of the environment variable that holds that user's password (default SCALANCE_PASSWORD)
#   SW_NEW_SECRET    name of the variable with the new password, for `sw.sh first-login` only (default
#                    SCALANCE_NEW_PASSWORD)
#   SW_SECRET_RUN    your secret manager's runner, put in front of the one process that reads the passwords,
#                    e.g. "op run --". Without it the variables must be set in the environment of the script (set
#                    them in your shell, never in the chat).
#   SW_SECRET_DIR    folder to run SW_SECRET_RUN in, when the runner finds its project from the current folder
#   SW_VIA           empty: ssh straight from this machine (needs python3 and ssh here).
#                    Otherwise the path of a vm.sh-like script that reaches a Windows machine on the switch's network
#                    (verbs `pipe <s> '<powershell>'` with stdin passed through, and `get <win path> <local>`), e.g.
#                    the plcnext-engineer skill's scripts/vm.sh. That machine needs only Windows PowerShell 5.1 and
#                    the OpenSSH client (ssh.exe, part of Windows 10/11).
#   SW_WIN_WORK      work folder on that Windows machine (default C:\agentwork\scalance)
#   SW_TFTP_PORT     UDP port of the TFTP receiver used by sw-get.sh / sw-backup.sh (default 50069)
#   SW_MYIP          address the switch sends files to (default: found from the route towards SW_HOST)
#   SW_TIMEOUT       seconds to wait for the prompt after one command (default 30)
#   SW_PAGER_OFF     command sent first in every session to switch the pager off (default below; empty = none;
#                    --More-- is answered either way)
SW_HOME=${SW_HOME:-$HOME/.scalance}
[ -f "$SW_HOME/config" ] && . "$SW_HOME/config"
SW_HOST=${SW_HOST:-}
SW_USER=${SW_USER:-admin}
SW_SECRET=${SW_SECRET:-SCALANCE_PASSWORD}
SW_NEW_SECRET=${SW_NEW_SECRET:-SCALANCE_NEW_PASSWORD}
SW_SECRET_RUN=${SW_SECRET_RUN:-}
SW_SECRET_DIR=${SW_SECRET_DIR:-.}
SW_VIA=${SW_VIA:-}
SW_WIN_WORK=${SW_WIN_WORK:-'C:\agentwork\scalance'}
SW_TFTP_PORT=${SW_TFTP_PORT:-50069}
SW_MYIP=${SW_MYIP:-}
SW_TIMEOUT=${SW_TIMEOUT:-30}
SW_PAGER_OFF=${SW_PAGER_OFF-}
export SW_HOME SW_HOST SW_USER SW_SECRET SW_NEW_SECRET SW_SECRET_RUN SW_SECRET_DIR SW_VIA SW_WIN_WORK SW_TFTP_PORT SW_MYIP SW_TIMEOUT SW_PAGER_OFF

secrets() {   # secrets NAME... : the values of those entries, one per line, on stdout (for a pipe, never for a terminal)
  local n miss=0
  if [ -n "$SW_SECRET_RUN" ]; then
    (cd "$SW_SECRET_DIR" && $SW_SECRET_RUN bash -c 'for n; do [ -n "${!n:-}" ] || exit 9; printf "%s\n" "${!n}"; done' _ "$@") 2>/dev/null \
      || { echo "secret: no value for one of: $* (through: $SW_SECRET_RUN)" >&2; return 1; }
  else
    for n; do [ -n "${!n:-}" ] || { echo "secret: the environment variable $n is not set (see scripts/config.sh)" >&2; miss=1; }; done
    [ $miss = 0 ] || return 1
    for n; do printf '%s\n' "${!n}"; done
  fi
}
