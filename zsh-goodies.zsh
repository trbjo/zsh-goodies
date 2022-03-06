ex() {
    if [ $# -eq 0 ]; then
        cd /home/tb/Export
    else
        cp "$@" /home/tb/Export
    fi
}

mkcd() {
  command mkdir -p "$1"
  cd "$1"
}

# nvm takes too long to source, we only source it if we need to
nvm() {
    if [[ ! -d /usr/share/nvm ]]; then
        print "Please install nvm first"
        return 1
    fi

    [ -z "$NVM_DIR" ] && export NVM_DIR="$HOME/.nvm"
    source /usr/share/nvm/nvm.sh
    source /usr/share/nvm/bash_completion
    source /usr/share/nvm/install-nvm-exec
    if [ $# -ne 0 ]; then
        nvm $@
    fi
}

if command -v curlie > /dev/null 2>&1; then
    curlie() {
         local -a myargs
         for string in $@; do
              if [[ $string == http* ]]; then
                   string=${string:gs/ /\%20}
              fi
              myargs+=$string
         done
         /usr/bin/curlie $myargs
    }
fi


gch() {
    [ ! -d "${HOME}/code" ] && mkdir -p "${HOME}/code"
    cd "${HOME}/code"

    if [[ "${#@}" -lt 1 ]]; then
        repo="$(wl-paste -n)"
    else
        repo="$1"
    fi

    if [[ "$repo" == *github.com* ]] && [[ ${repo:0:3} != "git" ]]; then
        # we are cloning from github, therefore automatically use ssh.
        repo="git@github.com:${${repo##*github.com/}%*/}.git"
    fi

    if [[ "$repo" == *git.sr.ht* ]] && [[ ${repo:0:3} != "git" ]]; then
        # we are cloning from sourcehut, therefore automatically use ssh.
        repo="git@git.sr.ht:${${repo##*git.sr.ht/}%*/}"
    fi

    git clone "${repo}" &&\
    cd "${${${repo/%\//}##*/}//.git/}"
    # the expr is read inside out. First, if the last char is '/' ('%' means last) we replace it with ''.
    # then we remove everything before the last '/' (string has now mutated), and finally, if the string
    # ends with .git, we remove that
}

_psql() {
     if [[ ${1:0:1} == "d" ]]; then
          myQuery="\\$@"
     else
          myQuery="$@"
     fi
     [[ -z ${PSQL_DB} ]] && print "PSQL_DB is unset" && return 1
     psql -U ${PSQL_USER:-postgres} -d ${PSQL_DB} <<< "$myQuery"
}
alias p='noglob _psql'

# Makes backspace delete the active selection if it has one
backward-delete-char() {
    if ((REGION_ACTIVE)) then
        if [[ $CURSOR -gt $MARK ]]; then
            BUFFER=$BUFFER[0,MARK]$BUFFER[CURSOR+1,-1]
            CURSOR=$MARK
        else
            BUFFER=$BUFFER[1,CURSOR]$BUFFER[MARK+1,-1]
        fi
        zle set-mark-command -n -1
    else
        if [[ "$BUFFER" == "${_ZSH_FILE_OPENER_CMD} " ]]; then
            printf "\033[J"
            zle .backward-delete-char
        fi
        zle .backward-delete-char
    fi
}
zle -N backward-delete-char
bindkey "^?" backward-delete-char

# this is meant to be bound to the same key as the terminal paste key
delete_active_selection() {
    if ((REGION_ACTIVE)) then
        if [[ $CURSOR -gt $MARK ]]; then
            BUFFER=$BUFFER[0,MARK]$BUFFER[CURSOR+1,-1]
            CURSOR=$MARK
        else
            BUFFER=$BUFFER[1,CURSOR]$BUFFER[MARK+1,-1]
        fi
        zle set-mark-command -n -1
    fi
}
zle -N delete_active_selection
bindkey "\ee" delete_active_selection

cdParentKey() {
    [[ $PWD == '/' ]] && return 0
    cd ..
    clear
    exa --group-directories-first
    print
    for cmd in $precmd_functions; do
        $cmd
    done
    zle       reset-prompt
}

zle -N                 cdParentKey
bindkey '^[[1;5A'      cdParentKey


fancy-ctrl-z () {
    if [[ $#BUFFER -eq 0 ]]
    then
        if [ -z $jobstates ]
        then
            BUFFER="htop"
            zle accept-line -w
        else
            BUFFER="fg"
            zle accept-line -w
        fi
    else
        # zle kill-buffer
        zle push-input -w
        zle clear-screen -w
    fi
}
zle -N fancy-ctrl-z
bindkey '^Z' fancy-ctrl-z


go_to_old_pwd() {
    if [ ! $BUFFER ] ; then
        if [[ $PWD != $OLDPWD ]]; then
            local precmd preexec
            for preexec in $preexec_functions
            do
                $preexec
            done
            cd - > /dev/null 2>&1
            print
            for precmd in $precmd_functions
            do
                $precmd
            done
            zle reset-prompt
        fi
    else
        #trim trailing spaces
        BUFFER="${BUFFER%%[[:blank:]]#}"
        zle accept-line
    fi
}
zle -N go_to_old_pwd
bindkey -e "^M" go_to_old_pwd


insert_doas() {
    [ $BUFFER ] && LBUFFER+="!" && return 0
    zle up-history
    BUFFER="doas $BUFFER"
    zle end-of-line
}
zle -N insert_doas
bindkey -e "!" insert_doas


wrapper() {
    [ $WIDGET == "wrapper-double" ] && quote='"' || quote="'"
    if ((REGION_ACTIVE)); then
        if [[ $CURSOR -gt $MARK ]]; then
            BUFFER=$BUFFER[0,MARK]$quote$BUFFER[MARK+1,CURSOR]$quote$BUFFER[CURSOR+1,-1]
            CURSOR+=2
        else
            BUFFER=$BUFFER[0,CURSOR]$quote$BUFFER[CURSOR+1,MARK]$quote$BUFFER[MARK+1,-1]
        fi
        zle set-mark-command -n -1
else
    LBUFFER+=$quote
fi
}
zle -N wrapper-single wrapper
zle -N wrapper-double wrapper
bindkey "\"" wrapper-double
bindkey "'" wrapper-single

expand-selection() {
        BEGIN=${#LBUFFER}
        END=0

        # if we have an active selection, we assume it was expanded with
        # this method and we ignore it by offsetting the indexes by 1
        if ((REGION_ACTIVE)); then

            # we store the current selection for the undo widget:
            UNDO_BEGIN_REGION=$MARK
            UNDO_END_REGION=$CURSOR

            let BEGIN=$(( ${#LBUFFER} - $CURSOR + $MARK -1))
            let END+=1
            # we check if we should expand for ' or "
            if [[ "${BUFFER[MARK]}" == '"' ]]; then
                quotematch=^\'$
            else
                quotematch=^\"$
            fi
        else
            # no selection, we expand for either
            quotematch=^\'\|\"$
        fi

        # traverse LBUFFER backwards to find beginning of quotes
        while ! [[ $LBUFFER[BEGIN] =~ $quotematch ]]; do
            if [[ $BEGIN == 1 ]];
            then
                return 0
            fi
            let BEGIN=$BEGIN-1
        done

        # we now know what matched, so we only check for the char
        # of the left match ignoring the regex,
        quotematch="${LBUFFER[BEGIN]}"

        # traverse forwards
        while [[ $RBUFFER[END] != $quotematch ]]; do
            if [[ $END == ${#RBUFFER} ]];
            then
                return 0
            fi
            let END=$END+1
        done

        LENGTHOFLSTRING=$(( ${#LBUFFER} - $BEGIN ))
        CURSOR=$BEGIN
        zle set-mark-command
        CURSOR+=$(( $LENGTHOFLSTRING + $END - 1))
        zle redisplay
}
zle -N expand-selection
bindkey -e "^s" expand-selection

undo() {
    if ((REGION_ACTIVE)); then
        zle set-mark-command -n -1
        zle set-mark-command
        MARK=$UNDO_BEGIN_REGION
        CURSOR=$UNDO_END_REGION
        zle redisplay
    else
        zle .undo
    fi
}
zle -N undo
bindkey -e "^_" undo



insert-brace() {
    LBUFFER+={
    RBUFFER=}$RBUFFER
    zle redisplay
}
zle -N insert-brace
bindkey "{" insert-brace

insert-bracket() {
    LBUFFER+=[
    RBUFFER=]$RBUFFER
    zle redisplay
}
zle -N insert-bracket
bindkey "[" insert-bracket



# get the length of a string
length() {
    input="$@"
    if [[ ${#input} -eq 0 ]]
    then
        [ $WAYLAND_DISPLAY ] && input=$(wl-paste --primary) || input=$CUTBUFFER
    fi
    python3 -c "print(len('$input'))"
}


function __calc_plugin {
    myargs="$@"
    python3 -c "from math import *; print($myargs)" | tee >(wl-copy -n -- 2> /dev/null)
    return 0
}
aliases[calc]='noglob __calc_plugin'
aliases[c]='noglob __calc_plugin'


# mount() {
#     mountpoint="/mnt"
#     if [ $# -eq 0 ]; then
#         newest_disk=$(ls /dev/sd* | sort --ignore-case --sort=version | tail -1)
#         doas mount $newest_disk -o uid=tb $mountpoint || return 1
#     else
#         doas mount /dev/"$1" -o uid=tb $mountpoint || return 1

#     fi
#     cd $mountpoint
#     clear
#     exa --group-directories-first
# }
# _mount() {_path_files -W /dev -g "sd*"}

# umount() {
#     if [[ "$(pwd)" =~ "/mnt*" ]]
#     then
#         cd
#     fi

#     if [ $# -eq 0 ]; then
#         doas umount /mnt
#     else
#         doas umount "$@"
#     fi
# }

# Store the current input, and restore it with a second ^q
# also store the cursor pos
remember() {
    # Nothing in buffer: get previous command.
    if [[ $#BUFFER -eq 0 ]]; then
        BUFFER="${stored}"
        CURSOR=$mycursor
        typeset -f _zsh_highlight > /dev/null && _zsh_highlight
    # Store current input.
    else
        mycursor=$CURSOR
        stored=$BUFFER
        zle kill-buffer
    fi
}
zle -N remember
bindkey '^Q' remember

# Makes tab repeat the last command if the buffer is empty.
# Otherwise workes as normal
repeat-last-command-or-complete-entry() {
    if [ -z "$BUFFER" ]; then
        zle up-history
        [[ "${BUFFER:0:2}" != "u " ]] && zle accept-line
    else
        [[ ! -z $pending_git_status_pid ]] && kill $pending_git_status_pid > /dev/null 2>&1 && unset pending_git_status_pid
        zle expand-or-complete
    fi
}
zle -N repeat-last-command-or-complete-entry
bindkey '\t' repeat-last-command-or-complete-entry

groot() {
    gittest=$(git rev-parse --show-toplevel) > /dev/null 2>&1 && cd $gittest || print "Not in a git dir"
}
