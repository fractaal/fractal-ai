#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════╗
# ║  CLAUDE CODE - ECAM STATUS DISPLAY                           ║
# ║  NASApunk avionics · ANSI color · adaptive row wrapping       ║
# ╚═══════════════════════════════════════════════════════════╝

export LC_ALL=C.UTF-8

JQ="/usr/bin/jq"
input=$(cat)

# ═══════════════════════════════════════════════════════════
#  DYNAMIC TERMINAL WIDTH DETECTION
#  Claude Code redirects stdin (JSON pipe) and captures stdout,
#  so we probe stderr and other FDs for the real terminal width.
# ═══════════════════════════════════════════════════════════
_detect_term_width() {
  # Claude Code fully detaches the statusline subprocess (/dev/tty severed,
  # stdin/stdout/stderr all redirected). Standard methods (tput, stty, $COLUMNS)
  # only return the 80-column default.
  #
  # Strategy: walk up the PPID chain to find the first ancestor with a real tty,
  # open that /dev/ttysNNN device, and TIOCGWINSZ ioctl for the true width.
  # TIOCGWINSZ is a kernel-specific magic number; pick it per $^O.
  #   Linux          0x5413
  #   macOS / BSD    0x40087468
  #   Solaris        0x5468
  # ps's no-tty sentinel also varies: "??" on macOS/BSD, "?" on Linux.
  perl -e '
    use POSIX;
    my %TIOCGWINSZ = (
      linux     => 0x5413,
      darwin    => 0x40087468,
      freebsd   => 0x40087468,
      netbsd    => 0x40087468,
      openbsd   => 0x40087468,
      dragonfly => 0x40087468,
      solaris   => 0x5468,
    );
    my $tiocgwinsz = $TIOCGWINSZ{$^O} // 0x40087468;
    my $pid = getppid();
    my $tty_dev;
    for (1..10) {
      my $out = `ps -o tty=,ppid= -p $pid 2>/dev/null`;
      chomp $out;
      my ($tty, $ppid) = split(/\s+/, $out);
      last unless defined $tty;
      if ($tty ne "?" && $tty ne "??" && $tty ne "-" && $tty ne "") {
        $tty_dev = "/dev/$tty";
        last;
      }
      $pid = $ppid // 1;
      last if $pid <= 1;
    }
    if ($tty_dev && open(my $fd, "<", $tty_dev)) {
      my $winsize = "\0" x 8;
      if (ioctl($fd, $tiocgwinsz, $winsize)) {
        my ($rows, $cols) = unpack("SS", $winsize);
        print "$cols\n";
        exit 0;
      }
    }
    print "0\n";
  ' 2>/dev/null
}
TERM_WIDTH=$(_detect_term_width)

# Claude Code's TUI chrome: left border + right-side token counter.
# Right side shows "N tokens" (up to "1000000 tokens" = 14 chars) plus padding.
# Left side has ~2 chars of border/margin.
# Total: 2 (left) + 14 (counter) + 4 (padding around counter) = 20
CC_PADDING=20
if [ "$TERM_WIDTH" -gt 0 ] 2>/dev/null; then
  USABLE_WIDTH=$((TERM_WIDTH - CC_PADDING))
  [ "$USABLE_WIDTH" -lt 40 ] && USABLE_WIDTH=40
else
  USABLE_WIDTH=40  # safe fallback (original hardcoded value)
fi

# 🔣 Nerd Font icons (PUA codepoints, generated via perl) 🔣
eval "$(perl -e '
  use utf8; binmode STDOUT, ":utf8";
  my %i = (SYS=>0xf2db, NAV=>0xf07c, GIT=>0xe725, CTX=>0xf080,
            CACHE=>0xf1c0, CALL=>0xf021, COST=>0xf155,
            LINES=>0xf1c9, LIMITS=>0xf0e7, SID=>0xf084, MDL=>0xf09d1);
  for (sort keys %i) { printf "I_%s=\"%s\"\n", $_, chr($i{$_}); }
')"

# 🎨 ANSI palette - ECAM avionics 🎨
R='\033[0m'       # reset
W='\033[1;97m'    # bright white  - section labels
G='\033[32m'      # green         - nominal values
BG='\033[1;32m'   # bold green    - bar filled, emphasis values
A='\033[33m'      # amber         - caution, cost
BA='\033[1;33m'   # bold amber    - bright warnings
RD='\033[31m'     # red           - removals, critical
BRD='\033[1;31m'  # bold red      - critical bar, alerts
C='\033[37m'      # white         - sub-labels, structure
BC='\033[1;97m'   # bright white  - icons
M='\033[35m'      # magenta       - session/meta
Y='\033[93m'      # bright yellow - cost dollar
D='\033[2m'       # dim           - secondary info
BD='\033[2;37m'   # dim grey      - bar empty

# 🔧 Helpers 🔧
tk() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" = "null" ] || [ "$n" = "0" ]; then printf "-"; return; fi
  if [ "$n" -ge 1000000 ]; then awk "BEGIN{printf \"%.1fM\",$n/1000000}"
  elif [ "$n" -ge 1000 ];  then awk "BEGIN{printf \"%.1fk\",$n/1000}"
  else printf "%s" "$n"; fi
}

met() {
  local ms="$1"
  if [ -z "$ms" ] || [ "$ms" = "null" ]; then printf "--:--"; return; fi
  local s=$((ms/1000))
  if [ "$s" -ge 3600 ]; then printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60))
  else printf "%02d:%02d" $((s/60)) $((s%60)); fi
}

# Inline bar: the text itself becomes the bar via background color fill.
# Left portion (proportional to pct) is rendered with a "filled" background;
# remainder uses a dim background. Foreground chosen for contrast.
inline_bar() {
  local pct="$1" text="$2"
  local len=${#text}
  local p
  p=$(printf '%.0f' "${pct:-0}")
  local fill
  fill=$(awk "BEGIN{ printf \"%.0f\", $len * $p / 100 }")
  [ "$fill" -gt "$len" ] && fill=$len
  [ "$fill" -lt 0 ] && fill=0

  # Filled-portion color by threat level (bg;fg)
  local bg_fill='\033[42;30m'      # green bg, black fg
  [ "$p" -ge 50 ] && bg_fill='\033[43;30m'   # amber bg, black fg
  [ "$p" -ge 75 ] && bg_fill='\033[41;97m'   # red bg, white fg
  local bg_empty='\033[48;5;238;38;5;250m'  # solid dark grey bg, light grey fg

  local filled_text="${text:0:$fill}"
  local empty_text="${text:$fill}"
  printf '%s%s%s%s\033[0m' "$bg_fill" "$filled_text" "$bg_empty" "$empty_text"
}

# ECAM status word - colored by severity
ctx_status() {
  local pct="$1"
  if [ -z "$pct" ]; then printf "${D}INIT${R}"; return; fi
  local p=$(printf '%.0f' "$pct")
  if   [ "$p" -lt 50 ]; then printf "${BG}NOMINAL${R}"
  elif [ "$p" -lt 75 ]; then printf "${BA}ADVISORY${R}"
  elif [ "$p" -lt 90 ]; then printf "${BA}CAUTION${R}"
  else                       printf "${BRD}CRITICAL${R}"; fi
}

# Visible length: interpret ANSI via %b, strip ESC sequences, count chars
# LC_ALL=C.UTF-8 (set at top) ensures ${#var} counts characters not bytes
vlen() {
  local stripped
  stripped=$(printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g')
  echo ${#stripped}
}

# ECAM dot-leader line: LABEL..........VALUE (fixed-width, not terminal-stretched)
# Usage: ecam_line <indent> <label> <value_ansi> <max_label_width>
ecam_line() {
  local indent="$1" label="$2" value="$3" max_lw="${4:-20}"
  local label_len=${#label}
  local dots=$((max_lw - label_len))
  [ "$dots" -lt 3 ] && dots=3
  local dot_str=$(printf '%*s' "$dots" '' | tr ' ' '.')
  printf '%b\n' "${indent}${W}${label}${D}${dot_str}${R}${value}"
}

# 📡 Extract all fields 📡
mdl=$(echo "$input"  | "$JQ" -r '.model.display_name // empty')
mid=$(echo "$input"  | "$JQ" -r '.model.id // empty')
ver=$(echo "$input"  | "$JQ" -r '.version // empty')
sid=$(echo "$input"  | "$JQ" -r '.session_id // empty')
cwd=$(echo "$input"  | "$JQ" -r '.workspace.current_dir // .cwd // empty')

csz=$(echo "$input"  | "$JQ" -r '.context_window.context_window_size // empty')
tin=$(echo "$input"  | "$JQ" -r '.context_window.total_input_tokens // empty')
tout=$(echo "$input" | "$JQ" -r '.context_window.total_output_tokens // empty')
upct=$(echo "$input" | "$JQ" -r '.context_window.used_percentage // empty')
rpct=$(echo "$input" | "$JQ" -r '.context_window.remaining_percentage // empty')
cin=$(echo "$input"  | "$JQ" -r '.context_window.current_usage.input_tokens // empty')
cout=$(echo "$input" | "$JQ" -r '.context_window.current_usage.output_tokens // empty')
cw=$(echo "$input"   | "$JQ" -r '.context_window.current_usage.cache_creation_input_tokens // empty')
cr=$(echo "$input"   | "$JQ" -r '.context_window.current_usage.cache_read_input_tokens // empty')
x200=$(echo "$input" | "$JQ" -r '.exceeds_200k_tokens // empty')

cost=$(echo "$input" | "$JQ" -r '.cost.total_cost_usd // empty')
tdur=$(echo "$input" | "$JQ" -r '.cost.total_duration_ms // empty')
adur=$(echo "$input" | "$JQ" -r '.cost.total_api_duration_ms // empty')
ladd=$(echo "$input" | "$JQ" -r '.cost.total_lines_added // empty')
lrm=$(echo "$input"  | "$JQ" -r '.cost.total_lines_removed // empty')

r5p=$(echo "$input"  | "$JQ" -r '.rate_limits.five_hour.used_percentage // empty')
r5t=$(echo "$input"  | "$JQ" -r '.rate_limits.five_hour.resets_at // empty')
r7p=$(echo "$input"  | "$JQ" -r '.rate_limits.seven_day.used_percentage // empty')
r7t=$(echo "$input"  | "$JQ" -r '.rate_limits.seven_day.resets_at // empty')

wtn=$(echo "$input"  | "$JQ" -r '.worktree.name // empty')
wtb=$(echo "$input"  | "$JQ" -r '.worktree.branch // empty')
agn=$(echo "$input"  | "$JQ" -r '.agent.name // empty')

# 🔀 Git branch 🔀
gbr=""
if [ -n "$cwd" ]; then
  gbr=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
fi

# 📂 Shorten CWD 📂
# Normalize backslashes to forward slashes first (Windows paths)
# This prevents \b in paths like C:\Users\benjude from being eaten by printf '%b'
scwd="$cwd"
if [ -n "$cwd" ]; then
  scwd=$(echo "$cwd" | sed 's|\\|/|g; s|^'"$HOME"'|~|; s|^/c/Users/[^/]*/|~/|')
  d=$(echo "$scwd" | tr '/' '\n' | wc -l)
  [ "$d" -gt 3 ] && scwd="./$(echo "$scwd" | rev | cut -d'/' -f1-2 | rev)"
fi

# ════════════════════════════════════════════════════════
#  BUILD ECAM SEGMENTS
# ════════════════════════════════════════════════════════
# Each segment: "LABEL value value value"
# Stored in parallel arrays: seg_text[] (with ANSI) and seg_vlen[] (visible width)

segments=()
seg_vlens=()

add_seg() {
  local text="$1"
  segments+=("$text")
  seg_vlens+=("$(vlen "$text")")
}

# 📁 CWD: working dir + branch + worktree + agent 📁
if [ -n "$scwd" ] || [ -n "$gbr" ]; then
  s="${BC}${I_NAV}${R}  ${W}CWD${R}  ${G}${scwd}${R}"
  [ -n "$gbr" ]  && s="${s}  ${BC}${I_GIT}${R} ${BG}${gbr}${R}"
  [ -n "$wtn" ]  && { s="${s}  ${BA}WT ${wtn}${R}"; [ -n "$wtb" ] && s="${s} ${BA}${wtb}${R}"; }
  [ -n "$agn" ]  && s="${s}  ${M}AGT ${agn}${R}"
  add_seg "$s"
fi

# 🤖 MDL: model id 🤖
if [ -n "$mid" ]; then
  add_seg "${BC}${I_MDL}${R}  ${W}MDL${R}  ${G}${mid}${R}"
fi

# 📊 CTX: inline bar folded into the readout, with cache read/write 📊
if [ -n "$upct" ]; then
  ui=$(printf '%.0f' "$upct")
  ctx_total=$((${cin:-0} + ${cw:-0} + ${cr:-0}))
  ctx_readout=" ${ui}%  ${ctx_total}/${csz} "
  s="${BC}${I_CTX}${R}  ${W}CTX${R}  $(inline_bar "$upct" "$ctx_readout")"
  [ "$x200" = "true" ] && s="${s}  ${BRD}?>200K${R}"
  if [ -n "$cw" ] || [ -n "$cr" ]; then
    s="${s}  ${C}CRD${R} ${BG}$(tk "$cr")${R}  ${C}CWR${R} ${G}$(tk "$cw")${R}"
  fi
  add_seg "$s"
fi
# 📡 COST + TIME 📡
if [ -n "$tdur" ] || { [ -n "$cost" ] && [ "$cost" != "0" ]; }; then
  tel="${BC}${I_COST}${R}"
  if [ -n "$cost" ] && [ "$cost" != "0" ]; then
    cf=$(awk "BEGIN{printf \"%.3f\",$cost}")
    tel="${tel}  ${Y}\$${cf}${R}"
  fi
  [ -n "$adur" ] && tel="${tel}  ${C}API${R} ${G}$(met "$adur")${R}"
  [ -n "$tdur" ] && tel="${tel}  ${C}WALL${R} ${G}$(met "$tdur")${R}"
  add_seg "$tel"
fi

# ⚡ LIMITS: rate limits ⚡
if [ -n "$r5p" ] || [ -n "$r7p" ]; then
  rl="${BC}${I_LIMITS}${R}  ${W}LIM${R}"
  if [ -n "$r5p" ]; then
    r5i=$(printf '%.0f' "$r5p")
    rl="${rl}  ${C}5H${R} ${BG}${r5i}%${R}"
    if [ -n "$r5t" ]; then
      r5time=$(date -d "@$r5t" '+%H:%M' 2>/dev/null || date -r "$r5t" '+%H:%M' 2>/dev/null || echo "?")
      rl="${rl} ${A}${r5time}${R}"
    fi
  fi
  if [ -n "$r7p" ]; then
    r7i=$(printf '%.0f' "$r7p")
    rl="${rl}  ${C}7D${R} ${BG}${r7i}%${R}"
    if [ -n "$r7t" ]; then
      r7time=$(date -d "@$r7t" '+%m/%d' 2>/dev/null || date -r "$r7t" '+%m/%d' 2>/dev/null || echo "?")
      rl="${rl} ${A}${r7time}${R}"
    fi
  fi
  add_seg "$rl"
fi

# 🔥 PACE: 5H burn-rate projection 🔥
# Tracks rate limit snapshots across invocations to detect unsustainable burn.
# Warns when projected to exhaust before the 5H window resets.
PACE_FILE="/tmp/claude-statusline-5h-pace.dat"
if [ -n "$r5p" ]; then
  now=$(date +%s)
  r5i=$(printf '%.0f' "$r5p")

  # Append current reading; keep last 60 entries (~5 min at 5s refresh)
  echo "$now $r5i" >> "$PACE_FILE"
  tail -60 "$PACE_FILE" > "${PACE_FILE}.tmp" && mv "${PACE_FILE}.tmp" "$PACE_FILE"

  # Reset tracking when the 5H window resets (usage drops significantly)
  _prev_pct=$(tail -2 "$PACE_FILE" | head -1 | awk '{print $2}')
  if [ -n "$_prev_pct" ] && [ "$r5i" -lt $((_prev_pct - 20)) ] 2>/dev/null; then
    echo "$now $r5i" > "$PACE_FILE"  # window reset, clear history
  fi

  # Need at least 2 readings spanning ≥30 seconds for a meaningful slope
  _oldest_line=$(head -1 "$PACE_FILE")
  _oldest_t=$(echo "$_oldest_line" | awk '{print $1}')
  _oldest_p=$(echo "$_oldest_line" | awk '{print $2}')
  _span=$((now - _oldest_t))

  # Minutes until 5H window resets
  _mins_to_reset="?"
  if [ -n "$r5t" ]; then
    _reset_epoch=$(echo "$r5t" | awk '{printf "%.0f", $1}')
    _mins_to_reset=$(( (_reset_epoch - now) / 60 ))
  fi

  if [ "$_span" -ge 30 ] 2>/dev/null; then
    # Calculate burn rate: % per minute (can be 0 if flat)
    _burn=$(awk "BEGIN{ printf \"%.2f\", ($r5i - $_oldest_p) / ($_span / 60.0) }")
    _burn_nz=$(awk "BEGIN{ print ($_burn > 0.01) }")

    if [ "$_burn_nz" = "1" ]; then
      _mins_to_100=$(awk "BEGIN{ printf \"%.0f\", (100 - $r5i) / $_burn }")
      _burn_display=$(awk "BEGIN{ printf \"%.1f\", $_burn }")

      # Sustainable burn rate: what %/min keeps you alive until reset
      _sust_rate="--"
      if [ "$_mins_to_reset" != "?" ] && [ "$_mins_to_reset" -gt 0 ] 2>/dev/null; then
        _sust_rate=$(awk "BEGIN{ printf \"%.1f\", (100 - $r5i) / $_mins_to_reset }")
      fi

      # Determine pace severity
      ECAM_PACE_SEV="NOMINAL"
      _pace_color="$BG"
      _lockout_gap=""
      if [ "$_mins_to_reset" != "?" ] 2>/dev/null; then
        _lockout_gap=$(( _mins_to_reset - _mins_to_100 ))
      fi

      if [ "$_mins_to_reset" != "?" ] && [ "$_mins_to_100" -lt "$_mins_to_reset" ] 2>/dev/null; then
        _pace_color="$BA"
        ECAM_PACE_SEV="ADVISORY"
      fi
      if [ "$_mins_to_100" -le 60 ] 2>/dev/null; then
        _pace_color="$BA"
        ECAM_PACE_SEV="CAUTION"
      fi
      if [ "$_mins_to_100" -le 20 ] 2>/dev/null; then
        _pace_color="$BRD"
        ECAM_PACE_SEV="CRITICAL"
      fi
      if [ -n "$_lockout_gap" ] && [ "$_lockout_gap" -ge 10 ] 2>/dev/null; then
        _pace_color="$BRD"
        ECAM_PACE_SEV="CRITICAL"
      fi

      # Stash values for ECAM block below
      ECAM_BURN="$_burn_display"
      ECAM_SUST="$_sust_rate"
      ECAM_ETA="$_mins_to_100"
      ECAM_RST="$_mins_to_reset"
      ECAM_PCT="$r5i"
      ECAM_COLOR="$_pace_color"

      # Cache efficiency (write = miss = expensive, read = hit = cheap)
      ECAM_CACHE_W=$(tk "${cw:-0}")
      ECAM_CACHE_R=$(tk "${cr:-0}")

      pace_seg="${BC}${I_LIMITS}${R}  ${W}PACE${R}  ${_pace_color}${ECAM_PACE_SEV}${R}"
      pace_seg="${pace_seg}  ${C}BURN${R} ${_pace_color}${_burn_display}%/m${R}"
      pace_seg="${pace_seg}  ${C}ETA${R} ${_pace_color}${_mins_to_100}m${R}"
      [ "$_mins_to_reset" != "?" ] && pace_seg="${pace_seg}  ${C}RST${R} ${G}${_mins_to_reset}m${R}"
      add_seg "$pace_seg"
    else
      ECAM_PACE_SEV="NOMINAL"
      pace_seg="${BC}${I_LIMITS}${R}  ${W}PACE${R}  ${BG}NOMINAL${R}  ${C}BURN${R} ${BG}0.0%/m${R}  ${C}ETA${R} ${D}--${R}"
      [ "$_mins_to_reset" != "?" ] && pace_seg="${pace_seg}  ${C}RST${R} ${G}${_mins_to_reset}m${R}"
      add_seg "$pace_seg"
    fi
  else
    pace_seg="${BC}${I_LIMITS}${R}  ${W}PACE${R}  ${D}INIT${R}  ${C}BURN${R} ${D}--${R}  ${C}ETA${R} ${D}--${R}"
    [ "$_mins_to_reset" != "?" ] && pace_seg="${pace_seg}  ${C}RST${R} ${G}${_mins_to_reset}m${R}"
    add_seg "$pace_seg"
  fi
fi

# 🏷 SID: session 🏷
[ -n "$sid" ] && add_seg "${M}${I_SID}${R}  ${M}SID ${sid:0:8}${R}"


# ════════════════════════════════════════════════════════
#  FLOW LAYOUT
#  Pack segments onto one line; wrap at segment boundaries
#  only when the next segment would exceed USABLE_WIDTH.
#  Never truncates — every segment is always shown in full.
# ════════════════════════════════════════════════════════

_sep="  ${C}│${R}  "
_sep_vl=5  # visible width of "  │  "

_line=""
_line_vl=0
for _i in "${!segments[@]}"; do
  _seg="${segments[$_i]}"
  _vl="${seg_vlens[$_i]}"

  if [ -z "$_line" ]; then
    _line="$_seg"
    _line_vl="$_vl"
    continue
  fi

  _proposed=$((_line_vl + _sep_vl + _vl))
  if [ "$_proposed" -le "$USABLE_WIDTH" ]; then
    _line="${_line}${_sep}${_seg}"
    _line_vl="$_proposed"
  else
    printf '%b\n' "$_line"
    _line="$_seg"
    _line_vl="$_vl"
  fi
done
[ -n "$_line" ] && printf '%b\n' "$_line"

# ════════════════════════════════════════════════════════
#  ECAM ADVISORY BLOCK
#  Detailed burn-rate advisories with actionable callouts.
#  Only emitted when pace severity > NOMINAL.
# ════════════════════════════════════════════════════════

_I="  "  # indent for sub-items
_LW=20   # fixed label width for dot-leaders

if [ "${ECAM_PACE_SEV}" = "ADVISORY" ]; then
  printf '\n\n'
  printf '%b\n' "${BA}  ⚡ LIMIT RATE${R}"
  printf '%b\n' "  ${BA}BURN ${ECAM_BURN}%/MIN${R}  ${BG}SUST ${ECAM_SUST}%/MIN${R}  ${BA}EXHAUST ${ECAM_ETA}M${R}  ${BG}RST ${ECAM_RST}M${R}"
  ecam_line "$_I" "  PROMPT SIZE" "${BA}REDUCE${R}" "$_LW"
  ecam_line "$_I" "  CTX WINDOW" "${BA}COMPACT${R}" "$_LW"
  ecam_line "$_I" "  CACHE MISSES" "${BG}MONITOR${R}" "$_LW"

elif [ "${ECAM_PACE_SEV}" = "CAUTION" ]; then
  printf '\n\n'
  printf '%b\n' "${BA}  ⚡ LIMIT PACE${R}"
  printf '%b\n' "  ${BA}BURN ${ECAM_BURN}%/MIN${R}  ${BG}SUST ${ECAM_SUST}%/MIN${R}  ${BA}EXHAUST ${ECAM_ETA}M${R}  ${BG}RST ${ECAM_RST}M${R}"
  ecam_line "$_I" "  CTX WINDOW" "${BA}COMPACT NOW${R}" "$_LW"
  ecam_line "$_I" "  BURN RATE" "${BA}≤${ECAM_SUST}%/MIN${R}" "$_LW"
  ecam_line "$_I" "  CACHE WRITE" "${BA}REDUCE${R}" "$_LW"
  ecam_line "$_I" "  NEW PROMPTS" "${BA}MINIMIZE${R}" "$_LW"

elif [ "${ECAM_PACE_SEV}" = "CRITICAL" ]; then
  printf '\n\n'
  printf '%b\n' "${BRD}  ⚡ LIMIT EXHAUST${R}"
  printf '%b\n' "  ${BRD}██ ${ECAM_ETA}M TO LOCKOUT ██${R}  ${BRD}BURN ${ECAM_BURN}%/MIN${R}  ${BG}SUST ${ECAM_SUST}%/MIN${R}"
  ecam_line "$_I" "  CONTEXT" "${BRD}COMPACT IMMEDIATELY${R}" "$_LW"
  ecam_line "$_I" "  SESSION" "${BRD}START NEW${R}" "$_LW"
  ecam_line "$_I" "  PROMPTS" "${BRD}STOP${R}" "$_LW"
  ecam_line "$_I" "  BURN RATE" "${BRD}≤${ECAM_SUST}%/MIN${R}" "$_LW"
fi
