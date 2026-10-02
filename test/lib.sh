# Sourced by test/render.sh. POSIX sh.
fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
check_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: got '$2', want '$3'"; fi
}
check_file() { if [ -f "$1" ]; then pass "exists $1"; else fail "missing $1"; fi; }
check_nofile() { if [ -e "$1" ]; then fail "should not exist $1"; else pass "absent $1"; fi; }
check_grep() { # desc file ERE-pattern
  if grep -Eq -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1: '$3' not in $2"; fi
}
check_nogrep() { # desc file ERE-pattern
  if grep -Eq -- "$3" "$2" 2>/dev/null; then fail "$1: '$3' found in $2"; else pass "$1"; fi
}
check_fgrep() { # desc file literal-string
  if grep -Fq -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1: '$3' not in $2"; fi
}
check_mode() { # desc path mode (e.g. 600)
  check_eq "$1" "$(stat -f %Lp "$2" 2>/dev/null)" "$3"
}
finish() {
  if [ "$fails" -eq 0 ]; then echo "all checks passed"; exit 0; fi
  echo "$fails check(s) failed"; exit 1
}
