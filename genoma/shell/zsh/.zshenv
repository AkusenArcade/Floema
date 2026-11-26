# Floema's marks for zsh. Floema points ZDOTDIR here and keeps the person's
# own in FLOEMA_ZDOTDIR: it is given back at once, their .zshenv read from
# it, and the marks added as hooks (OSC 133: prompt, command, output, end;
# OSC 7: the folder).
if [ -n "${FLOEMA_ZDOTDIR+x}" ]; then
    if [ -n "$FLOEMA_ZDOTDIR" ]; then ZDOTDIR="$FLOEMA_ZDOTDIR"; else unset ZDOTDIR; fi
    unset FLOEMA_ZDOTDIR
fi
[ -f "${ZDOTDIR:-$HOME}/.zshenv" ] && . "${ZDOTDIR:-$HOME}/.zshenv"

if [[ -o interactive ]]; then
    autoload -Uz add-zsh-hook
    __floema_precmd() {
        local s=$?
        print -n "\e]133;D;$s\a\e]7;file://${HOST:-localhost}$PWD\a\e]133;A\a"
        # The command's line starts where the prompt ends.
        [[ "$PS1" == *'133;B'* ]] || PS1="$PS1"$'%{\e]133;B\a%}'
        return $s
    }
    __floema_preexec() { print -n "\e]133;C\a" }
    add-zsh-hook precmd __floema_precmd
    add-zsh-hook preexec __floema_preexec
fi
