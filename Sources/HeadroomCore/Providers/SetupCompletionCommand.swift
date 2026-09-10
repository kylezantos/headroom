/// One shell contract for every official-CLI handoff. Keeping the trap and marker
/// writes shared prevents Claude and Codex from drifting on cleanup or relaunch state.
enum SetupCompletionCommand {
    static func wrap(
        _ invocation: String,
        marker: SetupCompletionMarker,
        mode: SetupHandoffMode
    ) -> String {
        let pendingBase = shellQuoted(marker.pendingPath)
        let completedBase = shellQuoted(marker.completedPath)
        let generationState = shellQuoted(AccountStorage.generationStatePath(marker))
        let modeName = mode == .deviceCode ? "deviceCode" : "standard"
        return """
        umask 077
        typeset -gr HEADROOM_SETUP_SCRIPT="$0"
        typeset -gr HEADROOM_SETUP_PENDING_BASE=\(pendingBase)
        typeset -gr HEADROOM_SETUP_COMPLETED_BASE=\(completedBase)
        typeset -gr HEADROOM_SETUP_GENERATION_STATE=\(generationState)
        typeset generation_state=""
        typeset generation_state_kind=""
        typeset handoff_generation=""
        typeset generation_state_trailing=""
        typeset prepared_marker=""
        typeset marker_kind=""
        typeset setup_purpose=""
        typeset marker_mode=""
        typeset marker_generation=""
        typeset marker_timestamp=""
        typeset trailing_field=""
        IFS= read -r generation_state < "$HEADROOM_SETUP_GENERATION_STATE" 2>/dev/null || exit 73
        IFS=: read -r generation_state_kind handoff_generation generation_state_trailing <<< "$generation_state"
        # R2M12: the active state may now carry the waiting clock's start as a third field.
        # It stays an allowlisted numeric; any other trailing content is an unrecognized
        # state file and still refuses the handoff.
        if [[ "$generation_state_kind" != "active"
              || ${#handoff_generation} -ne 32
              || "$handoff_generation" == *[^0-9a-f]*
              || ( -n "$generation_state_trailing"
                   && "$generation_state_trailing" != <->
                   && "$generation_state_trailing" != <->.<-> ) ]]; then
          exit 73
        fi
        # Headroom writes one active state per generation and never rewrites it in place, so
        # pinning the whole line keeps the cancellation guard below exact instead of
        # reconstructing a form the file can legitimately have two of.
        typeset -gr HEADROOM_SETUP_GENERATION_LINE="$generation_state"
        typeset -gr HEADROOM_SETUP_PENDING="${HEADROOM_SETUP_PENDING_BASE}.${handoff_generation}"
        typeset -gr HEADROOM_SETUP_COMPLETED="${HEADROOM_SETUP_COMPLETED_BASE}.${handoff_generation}"
        IFS= read -r prepared_marker < "$HEADROOM_SETUP_PENDING" 2>/dev/null || exit 73
        IFS=: read -r marker_kind setup_purpose marker_mode marker_generation marker_timestamp trailing_field <<< "$prepared_marker"
        if [[ "$marker_kind" != "opening"
              || ( "$setup_purpose" != "setup" && "$setup_purpose" != "reset" )
              || "$marker_mode" != "\(modeName)"
              || "$marker_generation" != "$handoff_generation"
              || -n "$trailing_field"
              || ( "$marker_timestamp" != <-> && "$marker_timestamp" != <->.<-> ) ]]; then
          exit 73
        fi
        typeset -gr HEADROOM_SETUP_OWNER="${setup_purpose}:\(modeName):${handoff_generation}:$$"
        print -r -- "$HEADROOM_SETUP_OWNER" > "$HEADROOM_SETUP_PENDING" || exit 73
        function headroom_setup_completed {
          typeset setup_status=$?
          typeset marker_owner=""
          typeset current_generation_state=""
          IFS= read -r marker_owner < "$HEADROOM_SETUP_PENDING" 2>/dev/null || true
          IFS= read -r current_generation_state < "$HEADROOM_SETUP_GENERATION_STATE" 2>/dev/null || true
          if [[ "$marker_owner" == "$HEADROOM_SETUP_OWNER"
                && "$current_generation_state" == "$HEADROOM_SETUP_GENERATION_LINE" ]]; then
            print -r -- "complete:${setup_purpose}:${handoff_generation}:${setup_status}" > "$HEADROOM_SETUP_COMPLETED"
            IFS= read -r current_generation_state < "$HEADROOM_SETUP_GENERATION_STATE" 2>/dev/null || true
            if [[ "$current_generation_state" != "$HEADROOM_SETUP_GENERATION_LINE" ]]; then
              rm -f -- "$HEADROOM_SETUP_COMPLETED"
            fi
          fi
          rm -f -- "$HEADROOM_SETUP_PENDING"
          rm -f -- "$HEADROOM_SETUP_SCRIPT"
        }
        trap headroom_setup_completed EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM
        \(invocation)
        exit $?
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
