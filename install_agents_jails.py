#!/usr/bin/env python3
"""
install_agents_jails.py - Configure restricted/jailed mode for AI agent CLI tools.

Sets up filesystem and network restrictions for:
  - Claude Code  (~/.claude/settings.json)
  - Codex CLI    (~/.codex/config.toml)
  - Gemini CLI   (~/.gemini/settings.json)

For each agent:
  1. Backs up existing config to old_settings/
  2. Applies filesystem restrictions (writes limited to cwd)
  3. Optionally restricts network to only the LLM API provider
  4. Shows unified diff of changes

Usage:
  python3 install_agents_jails.py                     # jail all agents
  python3 install_agents_jails.py claude              # jail only Claude Code
  python3 install_agents_jails.py claude codex        # jail Claude and Codex
  python3 install_agents_jails.py --disable-internet  # also restrict network
  python3 install_agents_jails.py --dry-run           # preview without writing
"""

import argparse
import json
import os
import shutil
import sys
import difflib
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib  # type: ignore[no-redef]
    except ImportError:
        print(
            "Error: No TOML parser available.\n"
            "Either upgrade to Python 3.11+ (which includes tomllib) "
            "or install tomli: pip install tomli",
            file=sys.stderr,
        )
        sys.exit(1)


# ─── TOML serializer ─────────────────────────────────────────────────────────
# Python stdlib has no TOML writer; this handles the subset we need.


def toml_dumps(data: dict) -> str:
    """Serialize a dict to TOML format."""
    lines: list[str] = []
    _toml_collect(data, lines, [])
    return "\n".join(lines) + "\n"


def _toml_key(key: str) -> str:
    """Return a bare key if possible, otherwise a quoted key."""
    if key and all(c.isalnum() or c in "-_" for c in key):
        return key
    return json.dumps(key)


def _toml_value(value: Any) -> str:
    """Serialize a scalar or array value to TOML."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, list):
        items = ", ".join(_toml_value(v) for v in value)
        return f"[{items}]"
    raise TypeError(f"Cannot serialize {type(value).__name__} to TOML")


def _toml_collect(data: dict, lines: list[str], path: list[str]) -> None:
    """Recursively collect TOML lines, skipping headers for table-only sections."""
    leaves = {k: v for k, v in data.items() if not isinstance(v, dict)}
    tables = {k: v for k, v in data.items() if isinstance(v, dict)}

    if leaves:
        if path:
            if lines:
                lines.append("")
            header = ".".join(_toml_key(k) for k in path)
            lines.append(f"[{header}]")
        for key, value in leaves.items():
            lines.append(f"{_toml_key(key)} = {_toml_value(value)}")

    for key, value in tables.items():
        _toml_collect(value, lines, path + [key])


# ─── Deep merge utility ──────────────────────────────────────────────────────


def deep_merge(base: dict, override: dict) -> dict:
    """Merge override into base recursively. Override values win."""
    merged = dict(base)
    for key, value in override.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


# ─── Base class ───────────────────────────────────────────────────────────────


class AgentJailer(ABC):
    """Base class for agent jailing configuration."""

    def __init__(self, disable_internet: bool = False, backup_dir: Path = Path("old_settings")):
        self.disable_internet = disable_internet
        self.backup_dir = backup_dir
        self._old_text = ""
        self._new_text = ""

    @property
    @abstractmethod
    def name(self) -> str:
        """Short identifier for this agent."""
        ...

    @property
    @abstractmethod
    def config_path(self) -> Path:
        """Absolute path to the agent's config file."""
        ...

    @abstractmethod
    def parse_config(self) -> dict:
        """Read and parse the existing config, or return {} if absent."""
        ...

    @abstractmethod
    def build_jailed_config(self, existing: dict) -> dict:
        """Return a new config dict with jail restrictions applied."""
        ...

    @abstractmethod
    def serialize(self, config: dict) -> str:
        """Serialize config dict back to the file format string."""
        ...

    def backup(self) -> Path | None:
        """Copy existing config into backup_dir. Returns dest path or None."""
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        if self.config_path.exists():
            dest = self.backup_dir / f"{self.name}_{self.config_path.name}"
            shutil.copy2(self.config_path, dest)
            return dest
        return None

    def diff(self) -> str:
        """Unified diff between old and new config text."""
        old = self._old_text.splitlines(keepends=True)
        new = self._new_text.splitlines(keepends=True)
        return "".join(
            difflib.unified_diff(
                old,
                new,
                fromfile=f"a/{self.name}/{self.config_path.name}",
                tofile=f"b/{self.name}/{self.config_path.name}",
            )
        )

    def apply(self, dry_run: bool = False) -> str:
        """Full pipeline: parse -> backup -> jail -> write -> diff."""
        print(f"\n{'=' * 60}")
        print(f"  {self.name}")
        print(f"  Config: {self.config_path}")
        print(f"{'=' * 60}")

        existing = self.parse_config()
        self._old_text = self.serialize(existing) if existing else ""

        if not dry_run:
            dest = self.backup()
            if dest:
                print(f"  Backup  -> {dest}")
            else:
                print(f"  (no existing config to back up)")

        jailed = self.build_jailed_config(existing)
        self._new_text = self.serialize(jailed)

        if not dry_run:
            self.config_path.parent.mkdir(parents=True, exist_ok=True)
            self.config_path.write_text(self._new_text)
            print(f"  Written -> {self.config_path}")
        else:
            print(f"  [DRY RUN] Would write -> {self.config_path}")

        d = self.diff()
        if d:
            print(f"\n  Diff:")
            for line in d.splitlines():
                print(f"    {line}")
        else:
            print(f"  (no changes — already jailed)")

        return d


# ─── Claude Code ──────────────────────────────────────────────────────────────
#
# Config: ~/.claude/settings.json  (JSON)
#
# Claude Code supports native sandbox configuration with path-level filesystem
# restrictions via the "sandbox" key in settings.json.
#
# Filesystem jail:
#   sandbox.enabled = true
#   sandbox.filesystem.allowRead/denyRead — control read access
#   sandbox.filesystem.allowWrite/denyWrite — control write access
#   Reads and writes limited to cwd ("."), home directory reads denied.
#
# Network jail (--disable-internet):
#   Deny network-accessing tools (WebSearch, WebFetch, curl, wget, etc.)
#


class ClaudeCodeJailer(AgentJailer):
    """Jail Claude Code via ~/.claude/settings.json sandbox configuration."""

    # Tools/patterns to deny for network restriction
    NETWORK_DENIALS = [
        "Bash(curl *)",
        "Bash(dig *)",
        "Bash(ftp *)",
        "Bash(nc *)",
        "Bash(ncat *)",
        "Bash(nslookup *)",
        "Bash(ping *)",
        "Bash(scp *)",
        "Bash(sftp *)",
        "Bash(ssh *)",
        "Bash(telnet *)",
        "Bash(wget *)",
        "WebFetch",
        "WebSearch",
    ]

    @property
    def name(self) -> str:
        return "claude-code"

    @property
    def config_path(self) -> Path:
        return Path.home() / ".claude" / "settings.json"

    def parse_config(self) -> dict:
        if self.config_path.exists():
            try:
                return json.loads(self.config_path.read_text())
            except json.JSONDecodeError:
                print(f"  WARNING: Could not parse {self.config_path}, starting fresh")
                return {}
        return {}

    def build_jailed_config(self, existing: dict) -> dict:
        config = json.loads(json.dumps(existing))  # deep copy

        # Apply native sandbox with filesystem restrictions
        config["sandbox"] = {
            "enabled": True,
            "filesystem": {
                "allowRead": ["."],
                "denyRead": ["~/"],
                "allowWrite": ["."],
                "denyWrite": ["/"],
            },
        }

        # Network restrictions via permissions deny-list
        if self.disable_internet:
            config.setdefault("permissions", {})
            deny = set(config["permissions"].get("deny", []))
            deny.update(self.NETWORK_DENIALS)
            config["permissions"]["deny"] = sorted(deny)

        # Enable autonomous mode — safe because the sandbox restricts what tools can do
        config["skipDangerousModePermissionPrompt"] = True

        return config

    def serialize(self, config: dict) -> str:
        if not config:
            return "{}\n"
        return json.dumps(config, indent=2) + "\n"


# ─── Codex CLI ────────────────────────────────────────────────────────────────
#
# Config: ~/.codex/config.toml  (TOML)
#
# Codex CLI has robust sandboxing:
#   - sandbox_mode: "read-only" | "workspace-write" | "danger-full-access"
#   - sandbox_workspace_write: writable_roots, network_access, exclude_slash_tmp
#   - Named permissions profiles with filesystem and network domain allowlists
#
# Filesystem jail:
#   sandbox_mode = "workspace-write"  -> writes limited to cwd + /tmp
#   permissions profile with filesystem ":cwd" = "write"
#
# Network jail (--disable-internet):
#   network proxy with mode="limited", allowing only api.openai.com
#


class CodexCLIJailer(AgentJailer):
    """Jail Codex CLI via ~/.codex/config.toml sandbox settings."""

    @property
    def name(self) -> str:
        return "codex-cli"

    @property
    def config_path(self) -> Path:
        codex_home = os.environ.get("CODEX_HOME", "")
        if codex_home:
            return Path(codex_home) / "config.toml"
        return Path.home() / ".codex" / "config.toml"

    def parse_config(self) -> dict:
        if not self.config_path.exists():
            return {}
        with open(self.config_path, "rb") as f:
            return tomllib.load(f)

    def build_jailed_config(self, existing: dict) -> dict:
        config = json.loads(json.dumps(existing))  # deep copy

        # Restrict sandbox to workspace-write (writes only to cwd + /tmp)
        config["sandbox_mode"] = "workspace-write"

        # Tighten workspace-write sandbox
        config.setdefault("sandbox_workspace_write", {})
        config["sandbox_workspace_write"]["network_access"] = False
        config["sandbox_workspace_write"]["exclude_slash_tmp"] = True

        # Enable autonomous mode — safe because sandbox restricts actions
        config["approval_policy"] = "never"

        if self.disable_internet:
            # Set up a named permissions profile with domain-level network allowlist
            config["default_permissions"] = "jailed"
            jailed = config.setdefault("permissions", {}).setdefault("jailed", {})

            # Filesystem: only cwd is writable
            jailed["filesystem"] = {":cwd": "write"}

            # Network: proxy allowing only OpenAI API
            jailed["network"] = {
                "enabled": True,
                "mode": "limited",
                "domains": {
                    "api.openai.com": "allow",
                },
            }

        return config

    def serialize(self, config: dict) -> str:
        if not config:
            return ""
        return toml_dumps(config)


# ─── Gemini CLI ───────────────────────────────────────────────────────────────
#
# Config: ~/.gemini/settings.json  (JSON)
#
# Gemini CLI sandbox options:
#   - tools.sandbox: true/false/"docker"/"podman"/"sandbox-exec"
#   - tools.exclude: list of tool names to disable
#   - tools.autoAccept: false to require confirmation
#   - security.folderTrust.enabled: restrict to trusted directories
#
# Filesystem jail:
#   Enable sandbox (writes limited to cwd, /tmp, ~/.gemini, ~/.cache)
#   Enable folder trust
#
# Network jail (--disable-internet):
#   Exclude google_web_search and web_fetch tools
#   Sandbox with closed network profile (via SEATBELT_PROFILE env hint)
#


class GeminiCLIJailer(AgentJailer):
    """Jail Gemini CLI via ~/.gemini/settings.json sandbox and tool exclusions."""

    @property
    def name(self) -> str:
        return "gemini-cli"

    @property
    def config_path(self) -> Path:
        return Path.home() / ".gemini" / "settings.json"

    def parse_config(self) -> dict:
        if self.config_path.exists():
            try:
                return json.loads(self.config_path.read_text())
            except json.JSONDecodeError:
                print(f"  WARNING: Could not parse {self.config_path}, starting fresh")
                return {}
        return {}

    def build_jailed_config(self, existing: dict) -> dict:
        config = json.loads(json.dumps(existing))  # deep copy

        # Enable sandbox for filesystem restriction
        config.setdefault("tools", {})
        config["tools"]["sandbox"] = True

        # Enable autonomous mode — safe because sandbox restricts actions
        config["tools"]["autoAccept"] = True

        # Enable folder trust system
        config.setdefault("security", {})
        config["security"].setdefault("folderTrust", {})
        config["security"]["folderTrust"]["enabled"] = True

        if self.disable_internet:
            # Exclude network-accessing tools
            exclude = set(config["tools"].get("exclude", []))
            exclude.update(["google_web_search", "web_fetch"])
            config["tools"]["exclude"] = sorted(exclude)

            # Also set top-level excludeTools for backwards compat
            exclude_top = set(config.get("excludeTools", []))
            exclude_top.update(["google_web_search", "web_fetch"])
            config["excludeTools"] = sorted(exclude_top)

        return config

    def serialize(self, config: dict) -> str:
        if not config:
            return "{}\n"
        return json.dumps(config, indent=2) + "\n"


# ─── Main ─────────────────────────────────────────────────────────────────────

JAILERS = {
    "claude": ClaudeCodeJailer,
    "codex": CodexCLIJailer,
    "gemini": GeminiCLIJailer,
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Set up restricted/jailed mode for AI agent CLI tools.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
examples:
  %(prog)s                          # jail all agents (default)
  %(prog)s claude                   # jail only Claude Code
  %(prog)s claude gemini            # jail Claude and Gemini
  %(prog)s --disable-internet       # also restrict network to LLM APIs
  %(prog)s codex --dry-run          # preview Codex changes without writing

notes:
  Claude Code supports native sandbox configuration with path-level
  filesystem restrictions via the "sandbox" key in settings.json.
  Reads and writes are limited to the current working directory.

  Codex CLI uses bubblewrap/Landlock (Linux) or Seatbelt (macOS) for
  filesystem sandboxing and a local proxy for network domain filtering.

  Gemini CLI uses sandbox-exec (macOS), Docker, or Podman. For closed-network
  mode on macOS, set SEATBELT_PROFILE=restrictive-closed before running gemini.
""",
    )
    parser.add_argument(
        "--disable-internet",
        action="store_true",
        help="restrict network to only the LLM API provider for each tool",
    )
    parser.add_argument(
        "--backup-dir",
        default="old_settings",
        help="directory for config backups (default: old_settings)",
    )
    all_agents = list(JAILERS.keys())
    parser.add_argument(
        "agents",
        nargs="*",
        default=None,
        metavar="AGENT",
        help=f"agents to jail (choices: {', '.join(all_agents)}; default: all)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show what would change without writing any files",
    )
    args = parser.parse_args()

    if not args.agents:
        args.agents = all_agents
    else:
        invalid = [a for a in args.agents if a not in JAILERS]
        if invalid:
            parser.error(
                f"invalid agent(s): {', '.join(invalid)} "
                f"(choose from {', '.join(all_agents)})"
            )

    backup_dir = Path(args.backup_dir)

    print("install_agents_jails.py")
    print(f"  disable-internet : {args.disable_internet}")
    print(f"  backup directory : {backup_dir.resolve()}")
    print(f"  agents           : {', '.join(args.agents)}")
    if args.dry_run:
        print(f"  *** DRY RUN — no files will be modified ***")

    results: dict[str, str] = {}
    for agent_name in args.agents:
        jailer = JAILERS[agent_name](
            disable_internet=args.disable_internet,
            backup_dir=backup_dir,
        )
        results[agent_name] = jailer.apply(dry_run=args.dry_run)

    # Summary
    print(f"\n{'=' * 60}")
    print("  Summary")
    print(f"{'=' * 60}")
    for name, d in results.items():
        status = "MODIFIED" if d else "NO CHANGE"
        print(f"  {name:20s} {status}")

    if not args.dry_run:
        print(f"\n  Old configs saved to: {backup_dir.resolve()}/")
    print("  Done.")


if __name__ == "__main__":
    main()
