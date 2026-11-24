#!/usr/bin/env python3
"""
update_gitconfig.py

Updates the global ~/.gitconfig file with settings from the local dotfiles/.gitconfig
while preserving:
1. The global [user] section (name and email).
2. The global [credential] and [credential "..."] sections.
3. Other global-only sections (e.g., [filter "lfs"], [protocol "sso"]) that do
   not exist in the local dotfiles/.gitconfig.

It also (re)generates a `git ned-private` alias in the [alias] section. Running
`git ned-private` inside any repository sets that repo's user.name/user.email to
this dotfiles repo's identity (read from the local .gitconfig [user] section) and
rewrites *all* local commits to use it. This is handy when you forget to set your
private name/email on a fresh repo and only notice after a few commits -- e.g.
when GitHub rejects a push with "GH007: Your push would publish a private email
address". After running it, force-push with `git push --force-with-lease`.

Before modifying ~/.gitconfig, a backup is created at ~/.gitconfig.backup.

With --stdin, the current global config is read from stdin and the merged
result is written to stdout (no backup, no file writes). chezmoi uses this mode
via home/modify_dot_gitconfig.tmpl, so `chezmoi apply` keeps ~/.gitconfig in
sync without clobbering machine-specific sections.
"""

import os
import sys
import shutil
import datetime

# Name of the convenience alias generated in the [alias] section.
ALIAS_NAME = "ned-private"

class ConfigSection:
    """Represents a section in a gitconfig file, preserving exact line formatting."""
    def __init__(self, header, lines):
        self.header = header  # e.g., '[user]' or '[credential "https://foo"]'
        self.lines = lines    # List of raw lines (including comments and newlines)

def normalize_header(header):
    """
    Normalizes a section header for reliable comparisons.
    e.g. '[credential "https://foo"]' -> 'credential "https://foo"'
    e.g. '[User]' -> 'user'
    """
    if not header:
        return ""
    content = header.strip().lstrip('[').rstrip(']')
    parts = content.split(None, 1)
    if len(parts) == 2:
        # The section name is case-insensitive, but subsection (in quotes) is case-sensitive
        return f"{parts[0].lower()} {parts[1]}"
    return parts[0].lower()

def parse_config_lines(lines):
    """Parses gitconfig lines into a list of ConfigSection objects."""
    sections = []
    current_header = ""
    current_lines = []

    for line in lines:
        stripped = line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            if current_header or current_lines:
                sections.append(ConfigSection(current_header, current_lines))
            current_header = stripped
            current_lines = []
        else:
            current_lines.append(line)

    if current_header or current_lines:
        sections.append(ConfigSection(current_header, current_lines))

    return sections

def parse_config(filepath):
    """Parses a gitconfig file into a list of ConfigSection objects."""
    if not os.path.exists(filepath):
        return []
    with open(filepath, 'r', encoding='utf-8') as f:
        return parse_config_lines(f.readlines())

def extract_user_identity(sections):
    """Returns (name, email) from the [user] section of the given sections."""
    name = None
    email = None
    for section in sections:
        if normalize_header(section.header) != 'user':
            continue
        for line in section.lines:
            if '=' not in line:
                continue
            key, value = line.split('=', 1)
            key = key.strip().lower()
            value = value.strip()
            if key == 'name':
                name = value
            elif key == 'email':
                email = value
    return name, email


def build_alias_lines(name, email):
    """
    Builds the raw [alias] lines (matching the .gitconfig formatting) for the
    `ned-private` alias, baking in the given name/email.

    The alias sets the current repo's user.name/user.email and then rewrites
    every commit (author and committer) on all refs to match, preserving the
    original commit dates.
    """
    return [
        '  {} = "!f() {{ \\\n'.format(ALIAS_NAME),
        "    git config user.name '{}'; \\\n".format(name),
        "    git config user.email '{}'; \\\n".format(email),
        '    n=\\"$(git config user.name)\\"; \\\n',
        '    e=\\"$(git config user.email)\\"; \\\n',
        '    FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --env-filter '
        '\\"export GIT_AUTHOR_NAME=\'$n\'; export GIT_AUTHOR_EMAIL=\'$e\'; '
        'export GIT_COMMITTER_NAME=\'$n\'; export GIT_COMMITTER_EMAIL=\'$e\'\\" '
        '-- --all; \\\n',
        '    echo \\"Rewrote all commits to $n <$e>. '
        'Now run: git push --force-with-lease\\"; \\\n',
        '  }; f"\n',
    ]


def inject_alias(sections, name, email):
    """
    Inserts (or replaces) the `ned-private` alias in the [alias] section of the
    given sections, in place. Creates an [alias] section if none exists.
    """
    if not name or not email:
        print("Warning: could not determine [user] name/email from local "
              "config; skipping '{}' alias.".format(ALIAS_NAME), file=sys.stderr)
        return

    alias_lines = build_alias_lines(name, email)

    alias_section = next(
        (s for s in sections if normalize_header(s.header) == 'alias'), None)
    if alias_section is None:
        sections.append(ConfigSection('[alias]', alias_lines))
        return

    # Drop any pre-existing ned-private alias (which may span continuation
    # lines) before appending the freshly generated one.
    kept = []
    skipping = False
    for line in alias_section.lines:
        if skipping:
            if not line.rstrip('\n').rstrip().endswith('\\'):
                skipping = False  # last physical line of the old alias
            continue
        if line.strip().startswith(ALIAS_NAME):
            if line.rstrip('\n').rstrip().endswith('\\'):
                skipping = True
            continue
        kept.append(line)

    alias_section.lines = kept + alias_lines


def merge_configs(local_sections, global_sections):
    """
    Merges local and global sections based on the specified rules:
    - Overwrite common sections with local ones.
    - Preserve global [user].
    - Preserve all global [credential] and [credential "..."] sections.
    - Preserve global-only sections (e.g., filter "lfs", protocol "sso").
    """
    local_by_header = {normalize_header(s.header): s for s in local_sections if s.header}
    global_by_header = {normalize_header(s.header): s for s in global_sections if s.header}
    
    merged_sections = []
    
    # Preserve initial non-section lines (if any) from the local config
    local_header_lines = next((s for s in local_sections if s.header == ""), None)
    if local_header_lines:
        merged_sections.append(local_header_lines)
        
    # Process local sections
    for section in local_sections:
        if not section.header:
            continue
        
        norm = normalize_header(section.header)
        
        if norm == 'user':
            # Keep the global user section instead of the local one
            if 'user' in global_by_header:
                merged_sections.append(global_by_header['user'])
            else:
                merged_sections.append(section)
        elif norm.startswith('credential') or norm.startswith('credential '):
            # Ignore local credential configurations; global ones are appended later
            continue
        else:
            # Use local config's version of the section
            merged_sections.append(section)
            
    # Process and append global credential and global-only sections
    for section in global_sections:
        if not section.header:
            continue
            
        norm = normalize_header(section.header)
        
        is_credential = norm.startswith('credential') or norm.startswith('credential ')
        is_global_only = norm not in local_by_header
        
        if is_credential or is_global_only:
            if norm == 'user':
                # User section has already been handled above
                if 'user' not in local_by_header:
                    merged_sections.append(section)
                continue
            merged_sections.append(section)
            
    return merged_sections

def render(sections):
    """Serializes ConfigSection objects back into gitconfig text."""
    out = []
    for section in sections:
        if section.header:
            out.append(section.header + '\n')
        out.extend(section.lines)
    return ''.join(out)


def load_local_sections():
    """Parses this repo's .gitconfig and injects the generated alias."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    local_config_path = os.path.join(script_dir, ".gitconfig")
    if not os.path.exists(local_config_path):
        print(f"Error: Local .gitconfig not found at {local_config_path}", file=sys.stderr)
        sys.exit(1)
    sections = parse_config(local_config_path)
    name, email = extract_user_identity(sections)
    inject_alias(sections, name, email)
    return local_config_path, sections, name, email


def main_stdin():
    """chezmoi modify_ mode: current config on stdin, merged config on stdout."""
    _, local_sections, _, _ = load_local_sections()
    global_sections = parse_config_lines(sys.stdin.read().splitlines(keepends=True))
    sys.stdout.write(render(merge_configs(local_sections, global_sections)))


def main():
    if '--stdin' in sys.argv[1:]:
        main_stdin()
        return

    global_config_path = os.path.join(os.path.expanduser("~"), ".gitconfig")

    local_config_path, local_sections, identity_name, identity_email = load_local_sections()
    print(f"Read local config from: {local_config_path}")
    if identity_name and identity_email:
        print(f"Configured '{ALIAS_NAME}' alias for identity: "
              f"{identity_name} <{identity_email}>")

    print(f"Reading global config from: {global_config_path}")
    global_sections = parse_config(global_config_path)

    # Back up global ~/.gitconfig if it exists
    if os.path.exists(global_config_path):
        backup_path = f"{global_config_path}.backup"
        try:
            shutil.copy2(global_config_path, backup_path)
            print(f"Successfully created backup at: {backup_path}")
        except Exception as e:
            print(f"Error: Failed to create backup at {backup_path}: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print("No existing global ~/.gitconfig to back up.")

    print("Merging configuration files...")
    merged = render(merge_configs(local_sections, global_sections))

    print(f"Writing merged configuration to: {global_config_path}")
    try:
        with open(global_config_path, 'w', encoding='utf-8') as f:
            f.write(merged)
        print("Successfully updated global ~/.gitconfig!")
    except Exception as e:
        print(f"Error: Failed to write to {global_config_path}: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
