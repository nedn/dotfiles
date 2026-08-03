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

  # Convert leading ~/ to $HOME/
  local file_path="$raw_path"
  if [[ "$file_path" == "~/"* ]]; then
    file_path="\$HOME/${file_path#\~/}"
  elif [ "$file_path" = "~" ]; then
    file_path="\$HOME"
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

  # Expand path for PATH checking
  local expanded_path
  expanded_path="$(eval echo "$file_path")"

  # Check if already present in export file
  local already_in_file=false
  if [ -f "$export_file" ]; then
    if grep -Fq "$file_path" "$export_file" 2>/dev/null || grep -Fq "$raw_path" "$export_file" 2>/dev/null; then
      already_in_file=true
    fi
  fi

  # Check if already present in current $PATH
  local already_in_path=false
  case ":$PATH:" in
    *":$expanded_path:"*) already_in_path=true ;;
    *":$raw_path:"*)      already_in_path=true ;;
  esac

  if [ "$already_in_file" = true ]; then
    echo "Path '$raw_path' is already exported in $export_file"
  else
    mkdir -p "$(dirname "$export_file")"
    if [ -s "$export_file" ] && [ -n "$(tail -c 1 "$export_file" 2>/dev/null)" ]; then
      echo "" >> "$export_file"
    fi
    echo "export PATH=\"$file_path:\$PATH\"" >> "$export_file"
    echo "Added 'export PATH=\"$file_path:\$PATH\"' to $export_file"
  fi

  # Update current shell PATH if not already present
  if [ "$already_in_path" = false ]; then
    export PATH="$expanded_path:$PATH"
  fi
}
