alias findip='curl -s icanhazip.com'

mkcd() {
  command mkdir -p "$1"
  cd "$1"
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
        local n=${(j:/:)seg[1,(I)$1*]}
        if [[ -n $n ]]; then
            $op /$n
        else
            print -u2 up: could not find prefix $1 in $PWD
            return 1
        fi
    esac
}

_up() {
    (( $#words > 2 )) && return
    compadd -V segments -- ${(Oas:/:)${PWD%/*}}
}
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
    [[ -z "$1" ]] && print -l "Variables:"\
    "PSQL_DB, PSQL_HOST, PSQL_DB" && return
    if [[ ${1:0:1} == "d" ]]; then
        myQuery="\\$@"
    else
        myQuery="$@"
    fi
    psql -U ${PSQL_USER:-postgres} -h ${PSQL_HOST:-localhost} -d ${PSQL_DB:-postgres} <<< "$myQuery"
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
            ($'\r') idx+=1
                (( $idx > ${#positions} )) && break ;;
            ($'\022') idx+=-1
                (( $idx == 0 )) && break ;;
            (*) zle -U "$key"
                break ;;
        esac
        CURSOR=${positions[$idx]}
        zle redisplay
    done
    region_highlight=(${region_highlight[1,$(( $#region_highlight - $#positions ))]})
}

zle -N _find_char_forward
bindkey -e "^T" _find_char_forward
zle -N find_char_backward
bindkey -e "^B" find_char_backward


typeset -ga __interesting_chars=("(" "{" "[" ")"  "}" "]" "'" '"' )
typeset -gA __corresponding_chars=("(" ")" ")" "(" "{" "}" "}" "{" "[" "]" "]" "[" "'" "'" '"' '"' )

expand-selection() {

    (( $#BUFFER == 0 )) && return

    if (($REGION_ACTIVE)) && [[ ${BUFFER[$(($CURSOR+1))]} == $__corresponding_chars[${BUFFER[$MARK]}] ]] && (( $#RBUFFER > 0 )) && [[ ${BUFFER[$MARK]} == $__corresponding_chars[${BUFFER[$(($CURSOR+1))]}] ]] && (( $#LBUFFER > 0 )); then
        MARK+=-1
        CURSOR+=1
        if (($REGION_ACTIVE)) && [[ ${BUFFER[$(($CURSOR+1))]} == $__corresponding_chars[${BUFFER[$MARK]}] ]] && (( $#RBUFFER > 0 )) && [[ ${BUFFER[$MARK]} == $__corresponding_chars[${BUFFER[$(($CURSOR+1))]}] ]] && (( $#LBUFFER > 0 )); then
            MARK+=-1
            CURSOR+=1
        fi
        zle redisplay
        return
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

gr() {
    gittest=$(git rev-parse --show-toplevel) > /dev/null 2>&1 && cd $gittest || print "Not in a git dir"
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

function _autosuggest_execute_or_clear_screen_or_ls() {
    if [[ $BUFFER ]]; then
        if [[ $POSTDISPLAY ]]; then
            BUFFER+="${POSTDISPLAY}"
            unset POSTDISPLAY
        fi
        zle .accept-line
    else
        local garbage termpos
        print -n "\033[6n\033[2J\033[3J\033[H"   # ask the terminal for the position and clear the screen
        read -d\[ garbage </dev/tty              # discard the first part of the response
        read -s -d R termpos </dev/tty               # store the position in bash variable 'termpos'
        typeset -i col="${termpos%%;*}"

        if (( col == 1 )); then
            exa --color=auto --group-directories-first 2> /dev/null || ls --color=auto --group-directories-first
        elif (( col <= 2 )) && [[ ${PROMPT_WS_SEP} ]]; then
            exa --color=auto --group-directories-first 2> /dev/null || ls --color=auto --group-directories-first
            print -Pn ${PROMPT_WS_SEP}
        fi
        preprompt
        zle reset-prompt
    fi
}
zle -N _autosuggest_execute_or_clear_screen_or_ls
bindkey -e '\e' _autosuggest_execute_or_clear_screen_or_ls

zmodload -i zsh/complist
bindkey -M menuselect '\e' .accept-line
