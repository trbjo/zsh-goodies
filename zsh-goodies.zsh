mkcd() {
  command mkdir -p "$1"
  cd "$1"
}

up() {
  local op=print
  [[ -t 1 ]] && op=cd
  case "$1" in
    '') up 1;;
    -*|+*) $op ~$1;;
    <->) $op $(printf '../%.0s' {1..$1});;
    @) local cdup; cdup=$(git rev-parse --show-cdup) && $op $cdup;;
    *) local -a seg; seg=(${(s:/:)PWD%/*})
       local n=${(j:/:)seg[1,(I)$1*]}
       if [[ -n $n ]]; then
         $op /$n
       else
         print -u2 up: could not find prefix $1 in $PWD
         return 1
       fi
  esac
}

_up() { compadd -V segments -- ${(Oas:/:)${PWD%/*}} }
compdef _up up

# nvm takes too long to source, we only source it if we need to
nvm() {
    if [[ ! -d /usr/share/nvm ]]; then
        print "Please install nvm first"
        return 1
    fi

    [[ -z "$NVM_DIR" ]] && export NVM_DIR="$HOME/.nvm"
    source /usr/share/nvm/nvm.sh
    source /usr/share/nvm/bash_completion
    source /usr/share/nvm/install-nvm-exec
    if [[ $# -ne 0 ]]; then
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


gcl() {
    [[ ! -d "${HOME}/code" ]] && mkdir -p "${HOME}/code"
    cd "${HOME}/code"
    local -a elements
    local repo
    elements=("${(@s:/:)1}")
    for ((i = 1; i < ${#elements}; i++)); do
        if [[ "${elements[$i]}" == *git.sr.ht* ]] || [[ "${elements[$i]}" == *github.com* ]]; then
            repo="git@${elements[$i]}:${elements[$i+1]}/${elements[$i+2]}"
            break
        fi
    done

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
        if [[ -z $jobstates ]]; then
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


insert_doas() {
    [[ $BUFFER ]] && LBUFFER+="!" && return 0
    zle up-history
    BUFFER="doas $BUFFER"
    zle end-of-line
}
zle -N insert_doas
bindkey -e "!" insert_doas


gentle_hl() {
    zle .forward-char
    zle .backward-char
}
zle -N gentle_hl

find_char_forward() {
    [[ -z "$RBUFFER" ]] && return
    find_char 1
}

find_char_backward() {
    [[ -z "$LBUFFER" ]] && return
    find_char 0
}

find_char() {
    local char
    read -k 1 char
    typeset -a lpositions rpositions
    for (( i = 1; i <= $#LBUFFER; i++ )); do
        if [[ "${LBUFFER[i]}" == "$char" ]]; then
            lpositions+=($i )
        fi
    done

    for (( i = 1; i <= $#RBUFFER; i++ )); do
        if [[ "${RBUFFER[i]}" == "$char" ]]; then
            rpositions+=( $(($i + $CURSOR)) )
        fi
    done

    typeset -a positions=(${lpositions[@]} ${rpositions[@]})
    if [[ ${#positions} -eq 0 ]]; then
        return
    fi

    typeset -i idx
    if [[ $1 == 1 ]]; then
        CURSOR=${rpositions[1]}
        idx=$(( ${#lpositions} + 1 ))
    else
        CURSOR=${lpositions[-1]}
        idx=$(( ${#lpositions} ))
    fi

    local pos
    for pos in ${positions}; do
        region_highlight+=("P$(( $pos -1 )) $pos bold,fg=cyan")
    done
    zle gentle_hl

    local key
    while true; do
        read -k 1 key
        case $key in
            $'\r') # forward
                idx+=1
                if (( $idx > ${#positions} )); then
                    CURSOR=${#BUFFER}
                    zle end-of-line
                    break
                fi
                CURSOR=${positions[$idx]}
                zle gentle_hl
                ;;
            $'\022') # backward
                idx=$(( $idx -1 ))
                if (( $idx == 0 )); then
                    CURSOR=0
                    zle beginning-of-line
                    break
                fi
                CURSOR=${positions[$idx]}
                zle gentle_hl
                ;;
            *) # any other key
                local __fc_feedkey=true
                break
                ;;
        esac
    done

    for (( i = 1; i <= $(( $#positions )); i++ )); do
        region_highlight[-1]=()
    done
    [[ -n $__fc_feedkey ]] && zle -U "$key"
}

zle -N find_char_forward
bindkey -e "^T" find_char_forward
zle -N find_char_backward
bindkey -e "^B" find_char_backward

expand-selection() {
    local quotematch
    local BEGIN=${#LBUFFER}
    local END=0

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
        if [[ $BEGIN == 1 ]]; then
            return 0
        fi
        let BEGIN=$BEGIN-1
    done

    # we now know what matched, so we only check for the char
    # of the left match ignoring the regex,
    quotematch="${LBUFFER[BEGIN]}"

    # traverse forwards
    while [[ $RBUFFER[END] != $quotematch ]]; do
        if [[ $END == ${#RBUFFER} ]]; then
            return 0
        fi
        let END=$END+1
    done

    LENGTHOFLSTRING=$(( ${#LBUFFER} - $BEGIN ))
    CURSOR=$BEGIN
    zle set-mark-command
    CURSOR+=$(( $LENGTHOFLSTRING + $END - 1))
    zle reset-prompt
}
zle -N expand-selection
bindkey -e "^s" expand-selection

undo() {
    if ((REGION_ACTIVE)); then
        zle set-mark-command -n -1
        zle set-mark-command
        MARK=$UNDO_BEGIN_REGION
        CURSOR=$UNDO_END_REGION
    else
        zle .undo
    fi
}
zle -N undo
bindkey -e "^_" undo


insert-bracket() {
    local leftmark='['
    local rightmark=']'
    zle insert-mark
}
zle -N insert-bracket
bindkey "[" insert-bracket

insert-brace() {
    local leftmark='{'
    local rightmark='}'
    zle insert-mark
}
zle -N insert-brace
bindkey "{" insert-brace

insert-parenthesis() {
    local leftmark='('
    local rightmark=')'
    zle insert-mark
}
zle -N insert-parenthesis
bindkey "(" insert-parenthesis

insert-double-quote() {
    local leftmark='"'
    local rightmark='"'
    zle insert-mark
}
zle -N insert-double-quote
bindkey '"' insert-double-quote

insert-single-quote() {
    local leftmark="'"
    local rightmark="'"
    zle insert-mark
}
zle -N insert-single-quote
bindkey "'" insert-single-quote

insert-mark() {
    if ((REGION_ACTIVE)); then
        if [[ $CURSOR -gt $MARK ]]; then
            BUFFER="$BUFFER[0,$MARK]${leftmark}$BUFFER[$MARK+1,$CURSOR]${rightmark}$BUFFER[$CURSOR+1,-1]"
            CURSOR+=2
        else
            BUFFER="$BUFFER[0,$CURSOR]${leftmark}$BUFFER[$CURSOR+1,$MARK]${rightmark}$BUFFER[$MARK+1,-1]"
        fi
        zle set-mark-command -n -1
    else
        LBUFFER+="$leftmark"
        if [[ -z "$RBUFFER" ]] && [[ "${LBUFFER: -2}" == " ${leftmark}" ]]; then
            RBUFFER="$rightmark"
        fi
    fi
}
zle -N insert-mark

# get the length of a string
length() {
    input="$@"
    if [[ ${#input} -eq 0 ]]
    then
        [[ $WAYLAND_DISPLAY ]] && input=$(wl-paste --primary) || input=$CUTBUFFER
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


# Store the current input, and restore it with a second ^q
# also store the cursor pos
remember() {
    # Nothing in buffer: get previous command.
    if [[ $#BUFFER -eq 0 ]]; then
        BUFFER="${stored}"
        CURSOR=$mycursor
        _zsh_highlight
    # Store current input.
    else
        mycursor=$CURSOR
        stored=$BUFFER
        zle kill-buffer
        zle reset-prompt
    fi
}
zle -N remember
bindkey '^Q' remember

# Makes tab repeat the last command if the buffer is empty.
# if the char to the right of the cursor is a 'closer', tab moves one char to the right
# Otherwise workes as normal
typeset -ga __closers=("\"" "'" "]" ")" "}")
repeat-last-command-or-complete-entry() {
    if [[ -z "$BUFFER" ]]; then
        zle up-history
        [[ "${BUFFER:0:2}" != "${_ZSH_FILE_OPENER_CMD} " ]] && zle accept-line
        return
    fi

    local right_char="${RBUFFER:0:1}"
    if [[ ${__closers[(i)$right_char]} -le 5 ]]; then
        zle .forward-char
        return
    fi

    [[ ! -z $pending_git_status_pid ]] && kill $pending_git_status_pid > /dev/null 2>&1 && unset pending_git_status_pid
    zle expand-or-complete
}
zle -N repeat-last-command-or-complete-entry
bindkey '\t' repeat-last-command-or-complete-entry
(( ${+ZSH_AUTOSUGGEST_CLEAR_WIDGETS} )) && ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(repeat-last-command-or-complete-entry)

groot() {
    gittest=$(git rev-parse --show-toplevel) > /dev/null 2>&1 && cd $gittest || print "Not in a git dir"
}

function _accept_autosuggestion() {
    BUFFER+="${POSTDISPLAY}"
    unset POSTDISPLAY
    _zsh_highlight
    return
}
zle -N _accept_autosuggestion
bindkey '^N' _accept_autosuggestion

function _autosuggest_execute_or_clear_screen_or_ls() {
    if [[ $BUFFER ]]; then
        BUFFER+="${POSTDISPLAY}"
        unset POSTDISPLAY
        zle .accept-line
    else
        print -n '\033[2J\033[3J\033[H' # hide cursor and clear screen
        if [[ "${LASTWIDGET}" == "_autosuggest_execute_or_clear_screen_or_ls" ]]; then
            redefine
        else
            redefine::reset
        fi
        preprompt
        print -Pn ${PROMPT_WS_SEP}
        zle reset-prompt
    fi
}
zle -N _autosuggest_execute_or_clear_screen_or_ls
bindkey -e '\e' _autosuggest_execute_or_clear_screen_or_ls

redefine::reset() {
    redefine::reset() {
        redefine() {
            exa --color=auto --group-directories-first 2> /dev/null || ls --color=auto --group-directories-first
            redefine() {
                redefine::reset
            }
        }
    }
    redefine::reset
    if [[ -z $ZLAST_COMMANDS ]]; then
        redefine
    fi
}

zmodload -i zsh/complist
bindkey -M menuselect '\e' .accept-line
