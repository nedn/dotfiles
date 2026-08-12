extract () {
  if [ -f $1 ] ; then
      case $1 in
          *.tar.bz2)   tar xvjf $1    ;;
          *.tar.gz)    tar xvzf $1    ;;
          *.bz2)       bunzip2 $1     ;;
          *.rar)       rar x $1       ;;
          *.gz)        gunzip $1      ;;
          *.tar)       tar xvf $1     ;;
          *.tbz2)      tar xvjf $1    ;;
          *.tgz)       tar xvzf $1    ;;
          *.zip)       unzip $1       ;;
          *.Z)         uncompress $1  ;;
          *.7z)        7z x $1        ;;
          *)           echo "don't know how to extract '$1'..." ;;
      esac
  else
      echo "'$1' is not a valid file!"
  fi
}

_canonical_path () {
  local p="$1"

  # Expand tilde (~ or ~/path or ~user/path)
  if [[ "$p" == "~" ]]; then
    p="$HOME"
  elif [[ "$p" == "~/"* ]]; then
    p="$HOME/${p#\~/}"
  elif [[ "$p" =~ ^~[a-zA-Z0-9._-]+(/|$) ]]; then
    local user_part="${p%%/*}"
    local rest="${p#"$user_part"}"
    local user_home
    user_home="$(eval echo "$user_part" 2>/dev/null)"
    if [ -n "$user_home" ]; then
      p="${user_home}${rest}"
    fi
  fi

  # Expand environment variables if any ($VAR or ${VAR})
  if [[ "$p" =~ \$ ]]; then
    p="$(eval echo "\"$p\"" 2>/dev/null)"
  fi

  # 1. Try realpath if available and succeeds
  if command -v realpath >/dev/null 2>&1; then
    local res
    if res="$(realpath "$p" 2>/dev/null)" && [ -n "$res" ]; then
      echo "$res"
      return 0
    fi
  fi

  # 2. Try python3 if available
  if command -v python3 >/dev/null 2>&1; then
    local res
    if res="$(python3 -c "import os, sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))" "$p" 2>/dev/null)" && [ -n "$res" ]; then
      echo "$res"
      return 0
    fi
  fi

  # 3. If directory exists, use cd -P & pwd -P
  if [ -d "$p" ]; then
    local res
    if res="$(cd -P "$p" 2>/dev/null && pwd -P)" && [ -n "$res" ]; then
      echo "$res"
      return 0
    fi
  fi

  # 4. If file exists, use cd -P on its dirname & pwd -P
  if [ -e "$p" ]; then
    local dir base res
    dir="$(dirname "$p")"
    base="$(basename "$p")"
    if res="$(cd -P "$dir" 2>/dev/null && pwd -P)" && [ -n "$res" ]; then
      echo "$res/$base"
      return 0
    fi
  fi

  # 5. Pure bash resolution for paths (including non-existent)
  if [[ "$p" != /* ]]; then
    p="$(pwd -P)/$p"
  fi

  # Normalize /./ and /../ and redundant slashes
  local oIFS="$IFS"
  IFS="/"
  local -a parts=($p)
  IFS="$oIFS"
  local -a stack=()
  for part in "${parts[@]}"; do
    if [ -z "$part" ] || [ "$part" = "." ]; then
      continue
    elif [ "$part" = ".." ]; then
      if [ ${#stack[@]} -gt 0 ]; then
        unset "stack[$((${#stack[@]}-1))]"
        stack=("${stack[@]}")
      fi
    else
      stack+=("$part")
    fi
  done

  local joined
  joined="$(IFS=/; echo "${stack[*]}")"
  echo "/$joined"
}

bash_export () {
  if [ -z "$1" ]; then
    echo "Usage: bash_export <path | export PATH=...>" >&2
    return 1
  fi

  local input="$*"
  local raw_path=""

  # Normalize input: handle 'export PATH=...', 'PATH=...', or bare path
  if [[ "$input" =~ ^[[:space:]]*(export[[:space:]]+)?PATH=[\"\']?(.*) ]]; then
    local extracted="${BASH_REMATCH[2]}"
    extracted="${extracted%[\"\']}"
    extracted="${extracted//:\$PATH/}"
    extracted="${extracted//:\$PATH/}"
    extracted="${extracted//\$PATH:/}"
    extracted="${extracted//\$PATH/}"
    raw_path="$extracted"
  else
    raw_path="$input"
  fi

  # Strip surrounding quotes and whitespace
  raw_path="${raw_path#\"}"
  raw_path="${raw_path%\"}"
  raw_path="${raw_path#\'}"
  raw_path="${raw_path%\'}"
  raw_path="$(echo "$raw_path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  if [ -z "$raw_path" ]; then
    echo "Usage: bash_export <path | export PATH=...>" >&2
    return 1
  fi

  # Expand to full canonical path
  local canonical_path
  canonical_path="$(_canonical_path "$raw_path")"

  if [ -z "$canonical_path" ]; then
    echo "Error: Could not resolve canonical path for '$raw_path'" >&2
    return 1
  fi

  # Determine target export file (~/.bash_exports or ~/.bash_export)
  local export_file="${BASH_EXPORTS_FILE:-}"
  if [ -z "$export_file" ]; then
    if [ -f "$HOME/.bash_exports" ]; then
      export_file="$HOME/.bash_exports"
    elif [ -f "$HOME/.bash_export" ]; then
      export_file="$HOME/.bash_export"
    else
      export_file="$HOME/.bash_exports"
    fi
  fi

  # Check for the exact line this function writes. A substring search is not
  # sufficient here: /opt/zig would otherwise match /opt/zig/zig-out/bin (or
  # even a comment) and incorrectly be reported as already exported.
  local already_in_file=false
  if [ -f "$export_file" ]; then
    local export_line="export PATH=\"$canonical_path:\$PATH\""
    local raw_export_line="export PATH=\"$raw_path:\$PATH\""
    if grep -Fxq "$export_line" "$export_file" 2>/dev/null || \
       grep -Fxq "$raw_export_line" "$export_file" 2>/dev/null; then
      already_in_file=true
    fi
  fi

  # Check if already present in current $PATH
  local already_in_path=false
  case ":$PATH:" in
    *":$canonical_path:"* | *":$canonical_path/:"*) already_in_path=true ;;
    *":$raw_path:"* | *":$raw_path/:"*)           already_in_path=true ;;
  esac

  if [ "$already_in_file" = true ]; then
    echo "Path '$canonical_path' is already exported in $export_file"
  else
    if ! mkdir -p "$(dirname "$export_file")"; then
      echo "Error: Could not create directory for $export_file" >&2
      return 1
    fi
    if [ -s "$export_file" ] && [ -n "$(tail -c 1 "$export_file" 2>/dev/null)" ]; then
      if ! printf '\n' >> "$export_file"; then
        echo "Error: Could not write to $export_file" >&2
        return 1
      fi
    fi
    if ! printf 'export PATH="%s:$PATH"\n' "$canonical_path" >> "$export_file"; then
      echo "Error: Could not write to $export_file" >&2
      return 1
    fi
    echo "Added 'export PATH=\"$canonical_path:\$PATH\"' to $export_file"
  fi

  # Update current shell PATH if not already present
  if [ "$already_in_path" = false ]; then
    export PATH="$canonical_path:$PATH"
  fi
}
