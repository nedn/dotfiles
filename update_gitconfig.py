#!/usr/bin/env python3
"""
update_gitconfig.py

Updates the global ~/.gitconfig file with settings from the local dotfiles/.gitconfig
while preserving:
1. The global [user] section (name and email).
2. The global [credential] and [credential "..."] sections.
3. Other global-only sections (e.g., [filter "lfs"], [protocol "sso"]) that do
   not exist in the local dotfiles/.gitconfig.

Before modifying ~/.gitconfig, a backup is created at ~/.gitconfig.backup.
"""

import os
import sys
import shutil
import datetime

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

def parse_config(filepath):
    """Parses a gitconfig file into a list of ConfigSection objects."""
    if not os.path.exists(filepath):
        return []
    
    sections = []
    current_header = ""
    current_lines = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
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

def main():
    home_dir = os.path.expanduser("~")
    global_config_path = os.path.join(home_dir, ".gitconfig")
    
    # Determine local config path relative to script directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    local_config_path = os.path.join(script_dir, ".gitconfig")
    
    if not os.path.exists(local_config_path):
        print(f"Error: Local .gitconfig not found at {local_config_path}", file=sys.stderr)
        sys.exit(1)
        
    print(f"Reading local config from: {local_config_path}")
    local_sections = parse_config(local_config_path)
    
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
        
    # Merge configs
    print("Merging configuration files...")
    merged_sections = merge_configs(local_sections, global_sections)
    
    # Write the merged config back
    print(f"Writing merged configuration to: {global_config_path}")
    try:
        with open(global_config_path, 'w', encoding='utf-8') as f:
            for section in merged_sections:
                if section.header:
                    f.write(section.header + '\n')
                for line in section.lines:
                    f.write(line)
        print("Successfully updated global ~/.gitconfig!")
    except Exception as e:
        print(f"Error: Failed to write to {global_config_path}: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
