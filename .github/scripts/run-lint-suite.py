#!/usr/bin/env python3
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Dict, List, Tuple

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
ARTIFACT_DIR = REPO_ROOT / "artifacts/policy"
CHANGED_PATHS_FILE = ARTIFACT_DIR / "changed-paths.txt"
SUPPRESSIONS_FILE = REPO_ROOT / "docs/governance/lint-suppressions.json"
DEFAULT_COMMAND_TIMEOUT_SECONDS = 300

CPP_EXTENSIONS = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx"}

CONFIG_FILES = [
    ".clang-tidy",
    ".clang-format",
    ".shellcheckrc",
    ".yamllint.yml",
    ".markdownlint-cli2.jsonc",
    "docs/governance/lint-suppressions.json",
]

EXPECTED_ENV = {
    "clang_tidy_major": "LLVM_MAJOR",
    "clang_format_major": "LLVM_MAJOR",
    "shellcheck": "SHELLCHECK_VERSION",
    "shfmt": "SHFMT_VERSION",
    "actionlint": "ACTIONLINT_VERSION",
    "yamllint": "YAMLLINT_VERSION",
    "markdownlint-cli2": "MARKDOWNLINT_CLI2_VERSION",
}

DEFAULT_PINS = {
    "clang_tidy_major": "18",
    "clang_format_major": "18",
    "shellcheck": "0.11.0",
    "shfmt": "3.12.0",
    "actionlint": "1.7.11",
    "yamllint": "1.38.0",
    "markdownlint-cli2": "0.21.0",
}


def command_timeout_seconds() -> int:
    raw_value = os.environ.get("LINT_COMMAND_TIMEOUT_SECONDS", str(DEFAULT_COMMAND_TIMEOUT_SECONDS)).strip()
    try:
        parsed = int(raw_value)
        if parsed > 0:
            return parsed
    except ValueError:
        pass
    return DEFAULT_COMMAND_TIMEOUT_SECONDS


def run_command(cmd: List[str]) -> Tuple[int, str]:
    timeout_seconds = command_timeout_seconds()
    try:
        proc = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout_seconds,
        )
        return proc.returncode, proc.stdout
    except FileNotFoundError:
        return 127, f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        return 124, f"command timed out after {timeout_seconds}s: {' '.join(cmd)}\n{output}"
    except OSError as exc:
        return 127, f"unable to execute command {' '.join(cmd)}: {exc}"


def collect_changed_paths() -> List[str]:
    def filtered(paths: List[str]) -> List[str]:
        blocked_prefixes = ("build/", "artifacts/")
        out: List[str] = []
        for path in paths:
            if path.startswith(blocked_prefixes):
                continue
            if not (REPO_ROOT / path).exists():
                continue
            out.append(path)
        return out

    if CHANGED_PATHS_FILE.exists():
        paths = [line.strip() for line in CHANGED_PATHS_FILE.read_text(encoding="utf-8").splitlines() if line.strip()]
        return filtered(paths)

    rc, output = run_command(["git", "ls-files"])
    if rc != 0:
        raise RuntimeError(f"Unable to determine tracked paths:\n{output}")
    CHANGED_PATHS_FILE.write_text(output, encoding="utf-8")
    return filtered([line.strip() for line in output.splitlines() if line.strip()])


def config_hash() -> str:
    sha = hashlib.sha256()
    for rel in CONFIG_FILES:
        path = REPO_ROOT / rel
        if not path.exists():
            continue
        sha.update(rel.encode("utf-8"))
        sha.update(b"\0")
        sha.update(path.read_bytes())
        sha.update(b"\0")
    return sha.hexdigest()


def observed_versions() -> Dict[str, str]:
    out: Dict[str, str] = {}
    commands = {
        "clang_tidy": ["clang-tidy", "--version"],
        "clang_format": ["clang-format", "--version"],
        "shellcheck": ["shellcheck", "--version"],
        "shfmt": ["shfmt", "--version"],
        "actionlint": ["actionlint", "-version"],
        "yamllint": ["yamllint", "--version"],
        # --no-globs avoids filesystem-dependent behavior in markdownlint-cli2.
        "markdownlint-cli2": ["markdownlint-cli2", "--no-globs", "--version"],
    }

    for name, cmd in commands.items():
        rc, output = run_command(cmd)
        if name == "markdownlint-cli2" and rc != 0:
            # Backward-compatible fallback if --no-globs is unsupported.
            rc, output = run_command(["markdownlint-cli2", "--version"])
        if rc != 0:
            out[name] = f"unavailable ({output.strip()})"
            continue
        out[name] = output.strip()
    return out


def parse_version(raw: str, default: str = "") -> str:
    match = re.search(r"(\d+\.\d+\.\d+)", raw)
    if match:
        return match.group(1)
    return default


def parse_markdownlint_cli2_version(raw: str, default: str = "") -> str:
    # Example output: "markdownlint-cli2 v0.21.0 (markdownlint v0.39.0)".
    match = re.search(r"\bmarkdownlint-cli2\b[^\r\n]*?\bv?(\d+\.\d+\.\d+)\b", raw, flags=re.IGNORECASE)
    if match:
        return match.group(1)
    return parse_version(raw, default)


def parse_major(raw: str, default: str = "") -> str:
    match = re.search(r"version\s+(\d+)", raw, flags=re.IGNORECASE)
    if match:
        return match.group(1)
    match = re.search(r"(\d+)\.\d+\.\d+", raw)
    if match:
        return match.group(1)
    return default


def verify_version_pins(observed: Dict[str, str]) -> Tuple[str, List[str], Dict[str, str], Dict[str, str]]:
    expected = {}
    for key, env_name in EXPECTED_ENV.items():
        expected[key] = os.environ.get(env_name, "").strip() or DEFAULT_PINS[key]
    errors: List[str] = []
    normalized_observed = {
        "clang_tidy_major": parse_major(observed.get("clang_tidy", "")),
        "clang_format_major": parse_major(observed.get("clang_format", "")),
        "shellcheck": parse_version(observed.get("shellcheck", "")),
        "shfmt": parse_version(observed.get("shfmt", "")),
        "actionlint": parse_version(observed.get("actionlint", "")),
        "yamllint": parse_version(observed.get("yamllint", "")),
        "markdownlint-cli2": parse_markdownlint_cli2_version(observed.get("markdownlint-cli2", "")),
    }

    if expected.get("clang_tidy_major") and normalized_observed["clang_tidy_major"] != expected["clang_tidy_major"]:
        errors.append(
            f"clang-tidy major mismatch: expected {expected['clang_tidy_major']}, observed {normalized_observed['clang_tidy_major'] or 'unknown'}"
        )
    if expected.get("clang_format_major") and normalized_observed["clang_format_major"] != expected["clang_format_major"]:
        errors.append(
            f"clang-format major mismatch: expected {expected['clang_format_major']}, observed {normalized_observed['clang_format_major'] or 'unknown'}"
        )

    normalized_expected = {
        "shellcheck": parse_version(expected.get("shellcheck", "")),
        "shfmt": parse_version(expected.get("shfmt", "")),
        "actionlint": parse_version(expected.get("actionlint", "")),
        "yamllint": parse_version(expected.get("yamllint", "")),
        "markdownlint-cli2": parse_markdownlint_cli2_version(expected.get("markdownlint-cli2", "")),
    }

    for key in ("shellcheck", "shfmt", "actionlint", "yamllint", "markdownlint-cli2"):
        if normalized_expected.get(key) and normalized_observed.get(key) != normalized_expected[key]:
            errors.append(
                f"{key} version mismatch: expected {normalized_expected[key]}, observed {normalized_observed.get(key) or 'unknown'}"
            )

    return ("pass" if not errors else "fail"), errors, expected, normalized_observed


def validate_suppressions() -> Tuple[str, List[str], int]:
    if not SUPPRESSIONS_FILE.exists():
        return "fail", [f"Missing suppression registry: {SUPPRESSIONS_FILE}"], 0

    try:
        payload = json.loads(SUPPRESSIONS_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return "fail", [f"Invalid suppression registry JSON: {exc}"], 0

    suppressions = payload.get("suppressions", [])
    if not isinstance(suppressions, list):
        return "fail", ["suppression registry must include a list at 'suppressions'"], 0

    required_fields = {"id", "tool", "scope", "rule_or_code", "reason", "owner", "created_on", "expires_on", "rollback_plan"}
    errors: List[str] = []
    now = dt.date.today()
    for idx, entry in enumerate(suppressions):
        if not isinstance(entry, dict):
            errors.append(f"suppressions[{idx}] must be an object")
            continue
        missing = sorted(required_fields - set(entry.keys()))
        if missing:
            errors.append(f"suppressions[{idx}] missing fields: {', '.join(missing)}")
        if entry.get("owner") != "self":
            errors.append(f"suppressions[{idx}] owner must be 'self'")
        expires_on = entry.get("expires_on", "")
        try:
            expires_date = dt.date.fromisoformat(expires_on)
            if expires_date < now:
                errors.append(f"suppressions[{idx}] is expired on {expires_on}")
        except ValueError:
            errors.append(f"suppressions[{idx}] invalid expires_on date '{expires_on}'")

    return ("pass" if not errors else "fail"), errors, len(suppressions)


def lint_cxx(files: List[str]) -> Dict[str, object]:
    result = {"status": "skip", "files_checked": files, "checks": {}, "errors": []}
    if not files:
        return result

    result["status"] = "pass"

    rc, output = run_command(["clang-format", "--dry-run", "--Werror", *files])
    result["checks"]["clang-format"] = "pass" if rc == 0 else "fail"
    if rc != 0:
        result["status"] = "fail"
        result["errors"].append("clang-format check failed")
        result["errors"].append(output.strip())

    build_dir = os.environ.get("CLANG_TIDY_BUILD_DIR", "build")
    compile_db = pathlib.Path(build_dir) / "compile_commands.json"
    if not compile_db.exists():
        result["checks"]["clang-tidy"] = "fail"
        result["status"] = "fail"
        result["errors"].append(f"Missing {compile_db}; required for clang-tidy")
        return result

    rc, output = run_command(["clang-tidy", "-p", build_dir, *files])
    result["checks"]["clang-tidy"] = "pass" if rc == 0 else "fail"
    if rc != 0:
        result["status"] = "fail"
        result["errors"].append("clang-tidy check failed")
        result["errors"].append(output.strip())
    return result


def lint_shell(files: List[str]) -> Dict[str, object]:
    result = {"status": "skip", "files_checked": files, "checks": {}, "errors": []}
    if not files:
        return result
    result["status"] = "pass"

    rc, output = run_command(["shfmt", "-d", "-i", "2", "-ci", *files])
    result["checks"]["shfmt"] = "pass" if rc == 0 else "fail"
    if rc != 0:
        result["status"] = "fail"
        result["errors"].append("shfmt check failed")
        result["errors"].append(output.strip())

    rc, output = run_command(["shellcheck", "-x", *files])
    result["checks"]["shellcheck"] = "pass" if rc == 0 else "fail"
    if rc != 0:
        result["status"] = "fail"
        result["errors"].append("shellcheck check failed")
        result["errors"].append(output.strip())
    return result


def lint_yaml(files: List[str]) -> Dict[str, object]:
    result = {"status": "skip", "files_checked": files, "checks": {}, "errors": []}
    if not files:
        return result
    result["status"] = "pass"

    workflow_files = [f for f in files if f.startswith(".github/workflows/")]
    if workflow_files:
        rc, output = run_command(["actionlint", *workflow_files])
        result["checks"]["actionlint"] = "pass" if rc == 0 else "fail"
        if rc != 0:
            result["status"] = "fail"
            result["errors"].append("actionlint check failed")
            result["errors"].append(output.strip())
    else:
        result["checks"]["actionlint"] = "skip"

    rc, output = run_command(["yamllint", "-c", ".yamllint.yml", *files])
    result["checks"]["yamllint"] = "pass" if rc == 0 else "fail"
    if rc != 0:
        result["status"] = "fail"
        result["errors"].append("yamllint check failed")
        result["errors"].append(output.strip())

    return result


def lint_docs(files: List[str]) -> Dict[str, object]:
    result = {"status": "skip", "files_checked": files, "checks": {}, "errors": []}
    if not files:
        return result
    result["status"] = "pass"

    rc, output = run_command(["markdownlint-cli2", "--no-globs", *files])
    result["checks"]["markdownlint-cli2"] = "pass" if rc == 0 else "fail"
    if rc != 0:
        result["status"] = "fail"
        result["errors"].append("markdownlint-cli2 check failed")
        result["errors"].append(output.strip())
    return result


def write_json(name: str, payload: Dict[str, object]) -> None:
    (ARTIFACT_DIR / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    changed_paths = collect_changed_paths()

    cpp_files = [p for p in changed_paths if pathlib.Path(p).suffix.lower() in CPP_EXTENSIONS]
    shell_files = [p for p in changed_paths if p.endswith(".sh")]
    yaml_files = [p for p in changed_paths if p.endswith((".yml", ".yaml"))]
    docs_files = [p for p in changed_paths if p.endswith(".md") and (p.startswith("docs/") or p.startswith(".github/"))]

    observed = observed_versions()
    version_status, version_errors, expected_versions, normalized_versions = verify_version_pins(observed)
    suppressions_status, suppressions_errors, suppressions_count = validate_suppressions()

    cpp_result = lint_cxx(cpp_files)
    shell_result = lint_shell(shell_files)
    yaml_result = lint_yaml(yaml_files)
    docs_result = lint_docs(docs_files)

    summary_checks = {
        "lint-cpp": cpp_result["status"],
        "lint-shell": shell_result["status"],
        "lint-yaml": yaml_result["status"],
        "lint-docs": docs_result["status"],
        "version-pinning": version_status,
        "suppression-registry": suppressions_status,
    }

    summary_errors: List[str] = []
    summary_errors.extend(version_errors)
    summary_errors.extend(suppressions_errors)
    summary_errors.extend(cpp_result["errors"])
    summary_errors.extend(shell_result["errors"])
    summary_errors.extend(yaml_result["errors"])
    summary_errors.extend(docs_result["errors"])

    overall_status = "pass"
    for status in summary_checks.values():
        if status == "fail":
            overall_status = "fail"
            break

    lint_summary = {
        "status": overall_status,
        "config_hash": config_hash(),
        "checks": summary_checks,
        "changed_paths_count": len(changed_paths),
        "files_scanned": {
            "cpp": len(cpp_files),
            "shell": len(shell_files),
            "yaml": len(yaml_files),
            "docs": len(docs_files),
        },
        "suppression_count": suppressions_count,
        "errors": summary_errors,
    }

    lane_correctness = {
        "status": overall_status,
        "lane": "correctness",
        "scope": "lint-and-static-analysis",
        "checks": summary_checks,
        "artifact_refs": [
            "artifacts/policy/lint-summary.json",
            "artifacts/policy/lint-tool-versions.json",
            "artifacts/policy/lint-cpp.json",
            "artifacts/policy/lint-shell.json",
            "artifacts/policy/lint-yaml.json",
            "artifacts/policy/lint-docs.json",
        ],
        "errors": summary_errors,
    }

    write_json("lint-tool-versions.json", {
        "status": version_status,
        "expected": expected_versions,
        "observed_raw": observed,
        "observed_normalized": normalized_versions,
        "errors": version_errors,
    })
    write_json("lint-cpp.json", cpp_result)
    write_json("lint-shell.json", shell_result)
    write_json("lint-yaml.json", yaml_result)
    write_json("lint-docs.json", docs_result)
    write_json("lint-summary.json", lint_summary)
    write_json("lane-correctness.json", lane_correctness)

    if overall_status != "pass":
        print("Lint suite failed. See artifacts/policy/lint-summary.json for details.")
        return 1

    print("Lint suite passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
