# Floema's marks for bash (OSC 133: prompt, command, output, end; OSC 7:
# the folder), after the person's own ~/.bashrc. Floema starts bash with
# --rcfile pointing here.
[ -f ~/.bashrc ] && . ~/.bashrc

__floema_precmd() {
    local status=$?
    printf '\e]133;D;%s\a' "$status"
    printf '\e]7;file://%s%s\a' "${HOSTNAME:-localhost}" "$PWD"
    printf '\e]133;A\a'
    # The command's line starts where the prompt ends.
    case "$PS1" in
        *'133;B'*) ;;
        *) PS1="$PS1"'\[\e]133;B\a\]' ;;
    esac
    return $status
}
PROMPT_COMMAND="__floema_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
# Printed after Return, before the command runs.
PS0='\[\e]133;C\a\]'"${PS0:-}"
