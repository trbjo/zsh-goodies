alias findip='curl --connect-timeout 0.5 -s icanhazip.com'

mkcd() {
  command mkdir -p "$1"
  cd "$1"
}

n() {
    local exit_code=$?
    local message title icon
    /usr/bin/gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1/session/auto --method org.freedesktop.login1.Session.SetIdleHint false > /dev/null 2>&1

    if [[ -z $@ ]]; then
        message="$(fc -ln -1 -1)"
        if [[ $exit_code -eq 0 ]]; then
            title="Success"
            icon="process-completed"
        else
            title="Failure $exit_code"
            icon="dialog-error"
        fi
    else
        if "$@"; then
            title="Success"
            icon="process-completed"
        else
            exit_code=$?
            title="Failure $exit_code"
            icon="dialog-error"
        fi
        message="$*"
    fi

    type swaymsg > /dev/null 2>&1 && swaymsg -q "output * power on" > /dev/null 2>&1
    printf "\033]777;notify;$title;$message\e"
    return "${exit_code:-0}"
}

up() {
    local op=print
    [[ -t 1 ]] && op=cd
    case "$1" in
        ('') up 1;;
        (-*|+*) $op ~$1;;
        (<->) $op $(printf '../%.0s' {1..$1});;
        (@) local cdup; cdup=$(git rev-parse --show-cdup) && $op $cdup;;
        (*) local -a seg; seg=(${(s:/:)PWD%/*})
        local n=${(j:/:)seg[1,(I)*$1*]}
        if [[ -n $n ]]; then
            $op /$n
        else
            print -u2 $0: could not find prefix $1 in $PWD
            return 1
        fi
    esac
}

_up() {
    (( $#words > 2 )) && return
    compadd -o nosort -M 'm:{a-zA-Z}={A-Za-z}' -M 'r:|[._-]=* r:|=*' -M 'l:|=* r:|=*' -- ${(s:/:)${PWD%/*}}
}
compdef _up up

lines() {
    for file in $@; do
        _colorizer "$file"
        print -n ' '
        cat "$file" | wc -l
    done
}


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
    local -a elements
    local repo
    elements=("${(@s:/:)1}")
    for ((i = 1; i < ${#elements}; i++)); do
        if [[ "${elements[$i]}" == *git.sr.ht* ]] || [[ "${elements[$i]}" == *github.com* ]]; then
            repo="git@${elements[$i]}:${elements[$i+1]}/${elements[$i+2]}"
            break
        fi
    done

    local localdir
    if [[ -z "$2" ]]; then
        localdir="${${${repo/%\//}##*/}//.git/}"
        # the expr is read inside out. First, if the last char is '/' ('%' means last) we replace it with ''.
        # then we remove everything before the last '/' (string has now mutated), and finally, if the string
        # ends with .git, we remove that
    else
        localdir="$2"
    fi

    git clone "${repo}" $localdir &&\
    cd $localdir
}

_psql() {
    [[ -z $PGDATABASE ]] && local PGDATABASE=postgres
    [[ -z $PGHOST ]] && local PGHOST=localhost
    [[ -z $PGPORT ]] && local PGPORT=5432
    [[ -z $PGUSER ]] && local PGUSER=postgres
    if [[ -z "$1" ]]; then
        psql -U ${PGUSER} -h ${PGHOST} -d ${PGDATABASE} ||\
        print -l "Current variables:"\
        "  PGDATABASE=${PGDATABASE}"\
        "  PGHOST=${PGHOST}"\
        "  PGPORT=${PGPORT}"\
        "  PGUSER=${PGUSER}"\
        "  PGPASSWORD=$PGPASSWORD"
        return
    fi
    if [[ ${#@} -eq 1 ]]; then
        psql -U ${PGUSER} -h ${PGHOST} -d ${PGDATABASE} <<< ${@}
    else
        psql -U ${PGUSER} -h ${PGHOST} -d ${PGDATABASE} ${@}
    fi
}
alias p='noglob _psql'

cdParentKey() {
    [[ $PWD == '/' ]] && return 0
    cd ..
    for cmd in $precmd_functions; do
        $cmd
    done
    zle .reset-prompt
}
zle -N                 cdParentKey
bindkey '^[[1;5A'      cdParentKey


fancy-ctrl-z () {
    if [[ -z $jobstates ]]; then
        BUFFER="htop"
    else
        BUFFER="fg"
    fi
    zle accept-line -w
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


_find_char_forward() {
    if [[ -n "${POSTDISPLAY}" ]]; then
        BUFFER+="${POSTDISPLAY}"
        unset POSTDISPLAY
        type -f _zsh_highlight > /dev/null && _zsh_highlight
        zle redisplay
    fi
    [[ -z "$RBUFFER" ]] && return
    find_char 1
}

find_char_backward() {
    [[ -z "$LBUFFER" ]] && return
    find_char 0
}

find_char () {
    type -f _zsh_highlight > /dev/null && _zsh_highlight
    local char
    read -k 1 char

    typeset -a lpositions rpositions
    for ((i = 1; i <= $#LBUFFER; i++ )) do
        [[ "${LBUFFER[i]}" == "$char" ]] && lpositions+=($i)
    done

    for ((i = 1; i <= $#RBUFFER; i++ )) do
        [[ "${RBUFFER[i]}" == "$char" ]] && rpositions+=($(($i + $CURSOR)))
    done

    typeset -i idx
    if [[ $1 == 1 ]]; then
        (( ${#rpositions} > 0 )) || return 0
        CURSOR=${rpositions[1]}
        idx=$(( ${#lpositions} + 1 ))
    else
        (( ${#lpositions} > 0 )) || return 0
        CURSOR=${lpositions[-1]}
        idx=$(( ${#lpositions} ))
    fi

    typeset -a positions=(${lpositions[@]} ${rpositions[@]})

    local pos
    for pos in ${positions}
    do
        region_highlight+="P$(( $pos -1 )) $pos bold,fg=cyan"
    done

    zle redisplay
    local key
    while read -k 1 key
    do
        case $key in
            ($CHAR_FWD_KEY) idx+=1
                (( $idx > ${#positions} )) && break ;;
            ($CHAR_BWD_KEY) idx+=-1
                (( $idx == 0 )) && break ;;
            (*) zle -U "$key"
                break ;;
        esac
        CURSOR=${positions[$idx]}
        zle redisplay
    done
    region_highlight=(${region_highlight[1,$(( $#region_highlight - $#positions ))]})
}

CHAR_FWD_KEY=$'\r'
CHAR_BWD_KEY=$'\022'

zle -N _find_char_forward
bindkey -e "^T" _find_char_forward
zle -N find_char_backward
bindkey -e "^G" find_char_backward


typeset -ga __interesting_chars=("(" "{" "[" ")"  "}" "]" "'" '"' )
typeset -gA __char_pairs=("(" ")" ")" "(" "{" "}" "}" "{" "[" "]" "]" "[" "'" "'" '"' '"' )
typeset -gA parens=("[" "]" "]" "[" )


# This function checks if the region is active, and if so, it deletes it
function delete-region-if-active {
    if ((REGION_ACTIVE)); then
        zle .kill-region
        zle .self-insert
        return
    fi
    zle .self-insert
}

# Replace the default self-insert widget with our custom one
zle -N self-insert delete-region-if-active

expand-selection() {

    (( $#BUFFER == 0 )) && return
    if (($REGION_ACTIVE)); then
        local cmatch mmatch clookup mlookup
        (( $#LBUFFER > 0 )) && (( $#RBUFFER > 0 )) || return
        cmatch="${BUFFER[$(($CURSOR+1))]}"
        mmatch="${BUFFER[$MARK]}"
        clookup="${__char_pairs[$mmatch]}"
        mlookup="${__char_pairs[$cmatch]}"
        if [[ $cmatch == $clookup ]] && [[ $mmatch == $mlookup ]]; then
            MARK+=-1
            CURSOR+=1
            (( $#LBUFFER > 0 )) && (( $#RBUFFER > 0 )) || return
            if [[ ${BUFFER[$(($CURSOR+1))]} == $clookup ]] && \
                [[ ${BUFFER[$MARK]} == $mlookup ]]; then
                MARK+=-1
                CURSOR+=1
            fi
            zle redisplay
            return
        fi
    fi

    typeset -a l_array=()
    typeset -a l_array_types=()

    typeset -i pop_this_many
    typeset -i single_quotes
    typeset -i double_quotes
    local var

    for (( i = 1; i <= $#LBUFFER; i++ )); do
        var=$__interesting_chars[(Ie)${LBUFFER[i]}]
        case $var in
            (0) continue ;;
            (<1-3>)
                l_array+=$i
                l_array_types+=$var
                ;;
            (<4-6>)
                (( ${#l_array} == 0 )) && continue
                if (( ${l_array_types[-1]} == ( $var - 3 ) )); then
                    l_array[-1]=()
                    l_array_types[-1]=()
                fi
                ;;
            (7)
                if (( single_quotes )); then
                    pop_this_many=$(($#l_array - single_quotes + 1))
                    for (( j = 1; j <= pop_this_many; j++ )); do
                        l_array_types[-1]=()
                        l_array[-1]=()
                    done
                    single_quotes=0
                else
                    l_array_types+=$var
                    l_array+=$i
                    single_quotes=$#l_array
                fi
                ;;
            (8)
                if (( double_quotes )); then
                    pop_this_many=$(($#l_array - double_quotes + 1))
                    for (( j = 1; j <= pop_this_many; j++ )); do
                        l_array_types[-1]=()
                        l_array[-1]=()
                    done
                    double_quotes=0
                else
                    l_array_types+=$var
                    l_array+=$i
                    double_quotes=$#l_array
                fi
                ;;
        esac
    done

    if (( $#l_array == 0 )); then
        return
    fi

    typeset -a r_array=()
    typeset -a r_array_types=()

    for (( i = 1; i <= $#RBUFFER; i++ )); do
        var=${__interesting_chars[(Ie)${RBUFFER[i]}]}
        case $var in
            (0) continue ;;
            (<1-3>)
                r_array+=$i
                r_array_types+=$var
                ;;
            (<4-6>)
                if (( ${#r_array} == 0 )); then
                    if (( ${l_array_types[-1]} == ( $var - 3 ) )); then
                        local rpos=$(( i + $#LBUFFER -1 ))
                        break
                    fi
                elif (( ${r_array_types[-1]} == ( $var - 3 ) )); then
                    r_array[-1]=()
                    r_array_types[-1]=()
                elif (( ${l_array_types[-1]} == ( $var - 3 ) )); then
                    local rpos=$(( i + $#LBUFFER -1 ))
                    break
                fi
                ;;
            (7)
                if (( single_quotes )); then
                    for (( j = ${#l_array_types}; j >= 1; j-- )); do
                        if (( ${l_array_types[j]} != $var )); then
                            l_array[-1]=()
                        else
                            break
                        fi
                    done
                    local rpos=$(( i + $#LBUFFER -1 ))
                    break
                fi
                ;;
            (8)
                if (( double_quotes )); then
                    for (( j = ${#l_array_types}; j >= 1; j-- )); do
                        if (( ${l_array_types[j]} != $var )); then
                            l_array[-1]=()
                        else
                            break
                        fi
                    done
                    local rpos=$(( i + $#LBUFFER -1 ))
                    break
                fi
                ;;
        esac
    done

    local lpos=${l_array[-1]}

    [[ -n $lpos ]] && [[ -n $rpos ]] || return

    zle set-mark-command
    MARK=$lpos
    CURSOR=$rpos
    zle redisplay
    return 0
}
zle -N expand-selection
bindkey -e "^Y" expand-selection

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
    local input
    input="$@"
    if [[ ${#input} -eq 0 ]]; then
        [[ $WAYLAND_DISPLAY ]] && input=${$(wl-paste --primary)//\'/\"} || input=$CUTBUFFER
    fi
    python3 -c "print(len('''$input'''))"
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
    if [[ $#BUFFER -eq 0 ]]; then # Nothing in buffer: get previous command.
        BUFFER="${stored}"
        CURSOR=$mycursor
        type -f _zsh_highlight > /dev/null && _zsh_highlight
    else # Store current input.
        mycursor=$CURSOR
        stored=$BUFFER
        zle .kill-buffer
        zle reset-prompt
    fi
}
zle -N remember
bindkey '^B' remember

# Makes tab repeat the last command if the buffer is empty.
# if the char to the right of the cursor is a 'closer', tab moves one char to the right
# Otherwise workes as normal
typeset -ga __closers=("\"" "'" "]" ")" "}")
typeset -ga __openers=("\"" "'" "[" "(" "{")
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

    zle expand-or-complete
}
zle -N repeat-last-command-or-complete-entry
bindkey '\t' repeat-last-command-or-complete-entry
(( ${+ZSH_AUTOSUGGEST_CLEAR_WIDGETS} )) && ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(repeat-last-command-or-complete-entry)

# navigate dirs with backspace/shift+backspace
setopt AUTO_PUSHD
typeset -a _dirstack
typeset -a mydirs
forward_dir() {
    # mydirs is not regulated when we push to the stack,
    # so we have to check for elements manually:
    [[ "${mydirs[-1]}" == "$PWD" ]] && mydirs[-1]=()
    [[  ${#mydirs} -lt 1 ]] && return
    print -n '\e[?25l'
    for (( i = 1; i <= ${#dirstack[@]}; i++ )) do
        if [[ "$dirstack[$i]" != "$_dirstack[$i]" ]]; then
            mydirs=()
            _dirstack=()
            print -n '\e[?25h'
            return
        fi
    done

    _dirstack=("$PWD" "$_dirstack[@]")
    cd "${mydirs[-1]}" > /dev/null 2>&1
    mydirs[-1]=()

    zle fzf-redraw-prompt
}
zle -N forward_dir
bindkey '^]' forward_dir

delete-char-or-region() {
    if ((REGION_ACTIVE)) then
        zle .kill-region
    else
        zle .delete-char
    fi
}
zle -N delete-char-or-region
bindkey "^D" delete-char-or-region

typeset -gA __matchers=("\"" "\"" "'" "'" "[" "]" "(" ")" "{" "}")
backward-delete-char() {
    # goes back in the cd history
    if [[ -z "$BUFFER" ]]; then
        print -n '\e[?25l'
        for (( i = 1; i <= ${#dirstack[@]}; i++ )) do
            if [[ "$dirstack[$i]" != "$_dirstack[$i]" ]]; then
                mydirs=()
                break
            fi
        done
        [[ "${dirstack[1]}" == "$PWD" ]] && popd > /dev/null 2>&1
        [[  ${#dirstack} -lt 1 ]] && print -n '\e[?25h' && return
        [[ "${mydirs[-1]}" == "$PWD" ]] || mydirs+=("$PWD")

        popd > /dev/null 2>&1
        _dirstack=($dirstack[@])
        zle fzf-redraw-prompt
        print -n '\e[?25h'
        return 0
    fi

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
            zle .backward-delete-char
        else
            local left_char="${LBUFFER: -1}"
            local left_left_char="${LBUFFER: -2:1}"
            local right_char="${RBUFFER:0:1}"
            if [[ -n "$left_char" ]] && [[ -n "$right_char" ]] && [[ "${__matchers[$left_char]}" == "$right_char" ]]; then
                zle .delete-char
            elif [[ -n "$left_char" ]] && [[ -n "$left_left_char" ]] && [[ "${__matchers[$left_left_char]}" == "$left_char" ]]; then
                zle .backward-delete-char
            fi
            zle .backward-delete-char
        fi
    fi
}
zle -N backward-delete-char
bindkey "^?" backward-delete-char

gr() {
    gittest="$(git rev-parse --show-toplevel)" && cd "$gittest"
}

function _accept_autosuggestion_or_mark_word() {

    if [[ -n "${POSTDISPLAY}" ]]; then
        BUFFER+="${POSTDISPLAY}"
        unset POSTDISPLAY
        type -f _zsh_highlight > /dev/null && _zsh_highlight
        zle redisplay
        return
    fi

    if (($REGION_ACTIVE)); then
        zle set-mark-command -n -1
        return
    fi

    typeset -i lpos rpos=$#BUFFER
    for ((i = $#LBUFFER; i >= 1; i-- )) do
        if [[ "${LBUFFER[i]}" =~ $'\t|\n| ' ]]; then
            lpos=$i
            break
        fi
    done
    for ((j = 1; j <= $#RBUFFER; j++ )) do
        if [[ "${RBUFFER[j]}" =~ $'\t|\n| ' ]]; then
            rpos=$(($j + $CURSOR -1 ))
            break
        fi
    done
    zle set-mark-command
    MARK=$lpos
    CURSOR=$rpos
    zle redisplay
}
zle -N _accept_autosuggestion_or_mark_word
bindkey '^N' _accept_autosuggestion_or_mark_word

kill-buffer() {
    [[ -z $BUFFER ]] && return 0

    local text a b

    if (( ! REGION_ACTIVE )); then
        a=0
        b=${#BUFFER}
    elif [[ $CURSOR -gt $MARK ]]; then
        a=$MARK
        b=$CURSOR
    else
        a=$CURSOR
        b=$MARK
    fi

    zle deactivate-region -w

    text="${BUFFER[$a+1,$b]}"
    text=$(print -r -n -- "$text" | base64 -w 0)
    printf "\033]52;c;$text\a"

    [[ $1 == "copy" ]] && return

    BUFFER=${BUFFER[0,$a]}${BUFFER[$b+1,$#BUFFER]}
    CURSOR=$a
}
zle -N kill-buffer
bindkey -e "^U" kill-buffer

copy_buffer() { kill-buffer copy }
zle -N copy_buffer
bindkey -e "\ew" copy_buffer

lolololol() {
    (( REGION_ACTIVE )) && zle .kill-region
    local response garbage
    printf '\033]52;c;?\a' > /dev/tty
    read -r -s -d 'c' garbage < /dev/tty
    read -r -s -d ';' garbage < /dev/tty
    read -d $'\a' -r response < /dev/tty
    LBUFFER+="$(print -r -n -- "$response" | base64 -d)"
    return 0
}
zle -N lolololol
# bindkey -e "^K" lolololol


# copies the full path of a file for later mv
cpa() {
    text="$(realpath "${1:-$PWD}")"
    printf "\033]52;c;$(print -r -n -- "$text" | base64 -w 0)\a$text"
}
cph() {
    text="${$(realpath "${1:-$PWD}")/#$HOME/~}"
    printf "\033]52;c;$(print -r -n -- "$text" | base64 -w 0)\a$text"
}
cpg() {
    text="$(realpath "${1:-$PWD}")"
    git_root="$(git rev-parse --show-toplevel)"
    text=${text//#$git_root/}
    printf "\033]52;c;$(print -r -n -- "$text" | base64 -w 0)\a$text"
}

function copytoclipboard() {
    read -s -r -d '' input
    printf "\033]52;c;$(print -r -n -- "$input" | base64 -w 0)\a$input"
}

alias -g CC=' |& copytoclipboard'

# ensures an active region is deleted first
autoload -Uz bracketed-paste
autoload -Uz bracketed-paste-magic
function my-bracketed-paste() {
    (( REGION_ACTIVE )) && zle .kill-region
    zle .bracketed-paste
}
zle -N bracketed-paste my-bracketed-paste
