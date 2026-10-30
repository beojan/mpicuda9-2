# shellcheck shell=bash
# Copyright (C) 2002-2026 CERN for the benefit of the ATLAS collaboration

# Terminal output helpers for the container build scripts. Source this file.
#
# Colours and the live progress line are used only when stdout is a terminal.
# Set NO_COLOR to turn off colours. Piped output stays plain text. The spinner
# and progress bar use the Nerd Font "extra progress" glyphs (U+EE00 to U+EE0B).
# Set UI_NERD=0 to use block and braille characters if your font lacks them.

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    UI_BOLD=$'\e[1m'
    UI_DIM=$'\e[2m'
    UI_RED=$'\e[31m'
    UI_GREEN=$'\e[32m'
    UI_YELLOW=$'\e[33m'
    UI_CYAN=$'\e[36m'
    UI_RESET=$'\e[0m'
else
    UI_BOLD= UI_DIM= UI_RED= UI_GREEN= UI_YELLOW= UI_CYAN= UI_RESET=
fi

if [[ ${UI_NERD:-1} != 0 ]]; then
    UI_SPINNER=($'\uEE06' $'\uEE07' $'\uEE08' $'\uEE09' $'\uEE0A' $'\uEE0B')
else
    UI_SPINNER=(⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷)
fi

# Give the cursor back. Scripts that use ui_run should call this from their
# EXIT trap, so an interrupted build does not leave the cursor hidden.
ui_show_cursor() {
    [[ -t 1 ]] && printf '\e[?25h'
    return 0
}

# Format a number of seconds as m:ss.
ui_elapsed() {
    printf '%d:%02d' $(($1 / 60)) $(($1 % 60))
}

# Print a progress bar. The filled part is green and the empty track is dim.
# Usage: ui_bar <percent 0-100> <width in cells>
#
# By default the bar is drawn with the Nerd Font "extra progress" glyphs, one
# per cell, with a distinct left end, middle and right end. With UI_NERD=0 it
# is drawn with block characters, and the last filled cell is drawn in eighths.
ui_bar() {
    local pct=$1 width=$2 i bar=
    if [[ ${UI_NERD:-1} != 0 ]]; then
        # Index 0, 1, 2 is the left end, middle and right end.
        local empty=($'\uEE00' $'\uEE01' $'\uEE02')
        local full=($'\uEE03' $'\uEE04' $'\uEE05') part filled=$((pct * width / 100))
        for ((i = 0; i < width; i++)); do
            if ((i == 0)); then part=0; elif ((i == width - 1)); then part=2; else part=1; fi
            if ((i < filled)); then
                bar+="${UI_GREEN}${full[part]}"
            else
                bar+="${UI_DIM}${empty[part]}"
            fi
        done
    else
        local blocks=(░ ▏ ▎ ▍ ▌ ▋ ▊ ▉ █) eighths eighths_filled=$((pct * width * 8 / 100))
        for ((i = 0; i < width; i++)); do
            eighths=$((eighths_filled - i * 8))
            ((eighths < 0)) && eighths=0
            ((eighths > 8)) && eighths=8
            if ((eighths == 0)); then bar+="${UI_DIM}${blocks[0]}"; else bar+="${UI_GREEN}${blocks[eighths]}"; fi
        done
    fi
    printf '%s%s' "$bar" "$UI_RESET"
}

# Run a command with its output sent to a log file, and show live progress.
#
# Usage: ui_run <title> <logfile> <parser> <command> [args...]
#
# The parser is a function that is called with the log file path about twice a
# second. It prints "<percent>|<label>" on one line. The percent may be empty
# when the progress is unknown, and the bar is then replaced by a spinner.
# The command's exit status is returned. On failure the end of the log is
# printed and the log file is kept. On success the log file is removed.
ui_run() {
    local title=$1 log=$2 parser=$3
    shift 3

    local start=$SECONDS rc=0 pid
    "$@" >"$log" 2>&1 &
    pid=$!

    if [[ -t 1 ]]; then
        local spin=("${UI_SPINNER[@]}") tick=0 cols pct label line
        cols=$(tput cols 2>/dev/null || echo 80)
        printf '\e[?25l'
        while kill -0 "$pid" 2>/dev/null; do
            pct= label=
            IFS='|' read -r pct label < <("$parser" "$log") || true
            line="${UI_CYAN}${spin[tick % ${#spin[@]}]}${UI_RESET} "
            if [[ -n $pct ]]; then
                line+="$(ui_bar "$pct" 24) $(printf '%3d%%' "$pct")  "
            else
                line+="${UI_BOLD}${title}${UI_RESET}  "
            fi
            line+="${UI_DIM}$(ui_elapsed $((SECONDS - start)))${UI_RESET}  "
            # Leave room for the part of the line that is already drawn.
            line+="${label:0:$((cols > 56 ? cols - 56 : 0))}"
            printf '\r\e[K%s' "$line"
            tick=$((tick + 1))
            sleep 0.5
        done
        printf '\r\e[K\e[?25h'
    else
        printf '==> %s\n' "$title"
    fi

    wait "$pid" || rc=$?

    local took
    took=$(ui_elapsed $((SECONDS - start)))
    if ((rc == 0)); then
        printf '%s✔%s %s %s(%s)%s\n' "$UI_GREEN" "$UI_RESET" "$title" "$UI_DIM" "$took" "$UI_RESET"
        rm -f -- "$log"
    else
        printf '%s✖%s %s failed with exit status %d after %s\n' "$UI_RED" "$UI_RESET" "$title" "$rc" "$took"
        printf '%sLast lines of the log:%s\n' "$UI_BOLD" "$UI_RESET"
        tail -n 30 -- "$log"
        printf '%sFull log: %s%s\n' "$UI_BOLD" "$log" "$UI_RESET"
    fi
    return "$rc"
}
