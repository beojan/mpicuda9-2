export PATH=/usr/local/cuda/bin:$PATH
unset PROMPT_COMMAND STARSHIP_PROMPT_COMMAND STARSHIP_SHELL STARSHIP_SESSION_KEY precmd_functions preexec_functions __bp_imported bash_preexec_imported
eval "$(starship init bash)"
PROMPT_COMMAND="starship_precmd"
