# Sourced by /etc/profile for a new interactive workshop SSH login.
[ -n "${BASH_VERSION:-}" ] || return 0
case $- in
    *i*) ;;
    *) return 0 ;;
esac
[[ ${USER:-} == team-[1-4] && -n ${SSH_TTY:-} && -t 0 && -t 1 ]] || return 0
[[ -z ${CHC_LOGIN_SHOWN:-} ]] || return 0
export CHC_LOGIN_SHOWN=1

workshop_login() {
    local rows columns
    IFS=' ' read -r rows columns <<< "$(stty size 2>/dev/null)"
    [[ $rows =~ ^[1-9][0-9]*$ ]] || rows=24
    [[ $columns =~ ^[1-9][0-9]*$ ]] || columns=80

    case ${TERM:-} in
        ''|dumb) ;;
        *) printf '\033[H\033[2J' ;;
    esac

    if (( columns >= 96 && rows >= 16 )); then
        cat <<'WORDMARK'
  ____                            _               _   _               _
 / ___|___  _ __ ___  _ __  _   _| |_ ___ _ __   | | | | __ _ _ __ __| |_      ____ _ _ __ ___
| |   / _ \| '_ ` _ \| '_ \| | | | __/ _ \ '__|  | |_| |/ _` | '__/ _` \ \ /\ / / _` | '__/ _ \
| |__| (_) | | | | | | |_) | |_| | ||  __/ |     |  _  | (_| | | | (_| |\ V  V / (_| | | |  __/
 \____\___/|_| |_| |_| .__/ \__,_|\__\___|_|     |_| |_|\__,_|_|  \__,_| \_/\_/ \__,_|_|  \___|
                     |_|

  ____ _       _
 / ___| |_   _| |__
| |   | | | | | '_ \
| |___| | |_| | |_) |
 \____|_|\__,_|_.__/
WORDMARK
    elif (( columns >= 48 && rows >= 24 )); then
        cat <<'WORDMARK'
  ____                            _
 / ___|___  _ __ ___  _ __  _   _| |_ ___ _ __
| |   / _ \| '_ ` _ \| '_ \| | | | __/ _ \ '__|
| |__| (_) | | | | | | |_) | |_| | ||  __/ |
 \____\___/|_| |_| |_| .__/ \__,_|\__\___|_|
                     |_|

 _   _               _
| | | | __ _ _ __ __| |_      ____ _ _ __ ___
| |_| |/ _` | '__/ _` \ \ /\ / / _` | '__/ _ \
|  _  | (_| | | | (_| |\ V  V / (_| | | |  __/
|_| |_|\__,_|_|  \__,_| \_/\_/ \__,_|_|  \___|

  ____ _       _
 / ___| |_   _| |__
| |   | | | | | '_ \
| |___| | |_| | |_) |
 \____|_|\__,_|_.__/
WORDMARK
    elif (( columns >= 22 )); then
        printf '%s\n' 'Computer Hardware Club'
    else
        printf '%s\n' Computer Hardware Club
    fi

    printf '\n'
}

workshop_login
unset -f workshop_login
