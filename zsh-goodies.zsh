ex() {
    if [ $# -eq 0 ]; then
        cd /home/tb/Export
    else
        cp "$@" /home/tb/Export
    fi
}


cdParentKey() {
    cd ..
    # print
    clear
    # zle      reset-prompt
    exa --group-directories-first
    vcs_info
    zle       reset-prompt
}

zle -N                 cdParentKey
bindkey '^[[1;3A'      cdParentKey


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


go_home() {
    if [ ! $BUFFER ] ; then
        if [[ $PWD != $HOME ]]; then
            cd
            zle redraw-prompt
        fi
    else
        zle accept-line
    fi
}
zle -N go_home
bindkey -e "^M" go_home


insert_sudo() {
    [ $BUFFER ] && LBUFFER+="!" && return 0
    zle up-history
    BUFFER="sudo $BUFFER"
    zle end-of-line
    # zle accept-line
    }
zle -N insert_sudo
bindkey -e "!" insert_sudo


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
    python3 -c "from math import *; print($myargs)" | tee >(wl-copy -- 2> /dev/null)
    return 0
}
aliases[calc]='noglob __calc_plugin'
aliases[c]='noglob __calc_plugin'



mount() {
    mountpoint="/mnt"
    if [ $# -eq 0 ]; then
        newest_disk=$(ls /dev/sd* | sort --ignore-case --sort=version | tail -1)
        sudo mount $newest_disk -o uid=tb $mountpoint || return 1
    else
        sudo mount /dev/"$1" -o uid=tb $mountpoint || return 1

    fi
    cd $mountpoint
    clear
    exa --group-directories-first
}
_mount() {_path_files -W /dev -g "sd*"}

umount() {
    if [[ "$(pwd)" =~ "/mnt*" ]]
    then
        cd
    fi

    if [ $# -eq 0 ]; then
        sudo umount /mnt
    else
        sudo umount "$@"
    fi
}



# Store the current input, and restore it with a second ^q
# also store the cursor pos
remember() {
    # Nothing in buffer: get previous command.
    if [[ $#BUFFER -eq 0 ]]; then
        LBUFFER="${stored}"
        CURSOR=$mycursor
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
    [ -z "$BUFFER" ] && zle up-history && zle accept-line || zle expand-or-complete
}
zle -N repeat-last-command-or-complete-entry
bindkey '\t' repeat-last-command-or-complete-entry


groot() {
    gittest=$(git rev-parse --show-toplevel) > /dev/null 2>&1 && cd $gittest || print "Not in a git dir"
}
