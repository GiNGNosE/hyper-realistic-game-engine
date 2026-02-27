#!/usr/bin/env python3
import json
import os
import pathlib
import re
import sys
from typing import Dict, List, Tuple

ARTIFACT_DIR = pathlib.Path("artifacts/policy")
RESULT_PATH = ARTIFACT_DIR / "pr-template-validation.json"

TEMPLATE_REQUIREMENTS: Dict[str, Dict[str, List[str]]] = {
    "feature": {
        "sections": [
            "Summary",
            "Scope And Risk",
            "Dual-Objective Evidence",
            "Test Matrix",
            "Artifact Links",
            "Governance Checklist",
        ],
        "checklist_sections": ["Test Matrix", "Governance Checklist"],
    },
    "bugfix": {
        "sections": [
            "Summary",
            "Root Cause",
            "Scope And Risk",
            "Dual-Objective Evidence",
            "Regression Coverage",
            "Test Matrix",
            "Artifact Links",
            "Governance Checklist",
        ],
        "checklist_sections": ["Test Matrix", "Governance Checklist"],
    },
    "governance-docs": {
        "sections": [
            "Summary",
            "Policy Impact",
            "Scope And Risk",
            "Validation Evidence",
            "Artifact Links",
            "Governance Checklist",
        ],
        "checklist_sections": ["Governance Checklist"],
    },
    "baseline-promotion": {
        "sections": [
            "Summary",
            "Promotion Intent Metadata",
            "Baseline Delta And Lineage",
            "Dual-Objective Evidence",
            "Test Matrix",
            "Artifact Links",
            "Governance Checklist",
        ],
        "checklist_sections": ["Test Matrix", "Governance Checklist"],
    },
}

BASELINE_REQUIRED_FIELDS = [
    "intent",
    "target_baseline_path",
    "baseline_index_update",
    "baseline_changelog_update",
]

PLACEHOLDER_PATTERN = re.compile(r"\b(TBD|TODO)\b|<fill|<replace", flags=re.IGNORECASE)
MARKER_PATTERN = re.compile(r"<!--\s*pr_template:\s*([a-z0-9-]+)\s*-->", flags=re.IGNORECASE)
HEADING_PATTERN = re.compile(r"^##\s+(.+?)\s*$", flags=re.MULTILINE)
CHECKED_PATTERN = re.compile(r"^\s*-\s*\[[xX]\]\s+", flags=re.MULTILINE)
CHECKLIST_ITEM_PATTERN = re.compile(r"^\s*-\s*\[([ xX])\]\s+(.+?)\s*$", flags=re.MULTILINE)


def normalize_heading(heading: str) -> str:
    value = re.sub(r"[^a-z0-9]+", " ", heading.lower())
    return re.sub(r"\s+", " ", value).strip()


def parse_sections(body: str) -> Dict[str, str]:
    matches = list(HEADING_PATTERN.finditer(body))
    sections: Dict[str, str] = {}
    for idx, match in enumerate(matches):
        name = normalize_heading(match.group(1))
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(body)
        sections[name] = body[start:end].strip()
    return sections


def get_event_payload() -> Tuple[Dict[str, object], List[str]]:
    errors: List[str] = []
    event_path = os.environ.get("GITHUB_EVENT_PATH", "").strip()
    if not event_path:
        return {}, ["Missing GITHUB_EVENT_PATH in environment"]

    path = pathlib.Path(event_path)
    if not path.exists():
        return {}, [f"GITHUB_EVENT_PATH does not exist: {event_path}"]

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return {}, [f"Unable to parse event payload JSON: {exc}"]
    return payload, errors


def validate_pr_body(pr_body: str, mode: str) -> Dict[str, object]:
    errors: List[str] = []
    checks: Dict[str, str] = {
        "marker_present": "pass",
        "template_type_known": "pass",
        "required_sections_present": "pass",
        "required_sections_non_empty": "pass",
        "placeholder_scan": "pass",
        "checklist_completion": "pass",
        "baseline_promotion_metadata": "pass",
        "artifact_links_section": "pass",
    }

    marker = MARKER_PATTERN.search(pr_body)
    if not marker:
        checks["marker_present"] = "fail"
        checks["template_type_known"] = "fail"
        errors.append("PR body must include a template marker like <!-- pr_template: feature -->")
        return {
            "status": "fail",
            "mode": mode,
            "template_type": "",
            "checks": checks,
            "errors": errors,
        }

    template_type = marker.group(1).strip().lower()
    requirements = TEMPLATE_REQUIREMENTS.get(template_type)
    if not requirements:
        checks["template_type_known"] = "fail"
        errors.append(
            f"Unknown PR template type '{template_type}'. "
            "Allowed: feature, bugfix, governance-docs, baseline-promotion."
        )
        return {
            "status": "fail",
            "mode": mode,
            "template_type": template_type,
            "checks": checks,
            "errors": errors,
        }

    parsed = parse_sections(pr_body)

    for section in requirements["sections"]:
        key = normalize_heading(section)
        content = parsed.get(key, "")
        if not content:
            checks["required_sections_present"] = "fail"
            checks["required_sections_non_empty"] = "fail"
            errors.append(f"Missing or empty required section: '{section}'")

    for section in requirements["sections"]:
        key = normalize_heading(section)
        content = parsed.get(key, "")
        if content and PLACEHOLDER_PATTERN.search(content):
            checks["placeholder_scan"] = "fail"
            errors.append(f"Placeholder text detected in section '{section}'. Replace TODO/TBD placeholders.")

    for section in requirements.get("checklist_sections", []):
        key = normalize_heading(section)
        content = parsed.get(key, "")
        if not content:
            continue

        checklist_items = CHECKLIST_ITEM_PATTERN.findall(content)
        if not checklist_items:
            checks["checklist_completion"] = "fail"
            errors.append(f"Section '{section}' must include checklist items.")
            continue

        unchecked_labels = [label.strip() for state, label in checklist_items if state.lower() != "x"]
        if unchecked_labels:
            checks["checklist_completion"] = "fail"
            errors.append(
                f"Section '{section}' has incomplete checklist items: "
                + ", ".join(unchecked_labels)
            )

    artifact_links = parsed.get(normalize_heading("Artifact Links"), "")
    if artifact_links and "artifacts/" not in artifact_links:
        checks["artifact_links_section"] = "fail"
        errors.append("Artifact Links section must reference at least one artifacts/ path.")

    if template_type == "baseline-promotion":
        metadata = parsed.get(normalize_heading("Promotion Intent Metadata"), "")
        missing_fields: List[str] = []
        for field in BASELINE_REQUIRED_FIELDS:
            pattern = re.compile(rf"^\s*-\s*{re.escape(field)}\s*:\s*(.+)$", flags=re.MULTILINE)
            matched = pattern.search(metadata)
            if not matched or not matched.group(1).strip():
                missing_fields.append(field)
        if missing_fields:
            checks["baseline_promotion_metadata"] = "fail"
            errors.append(
                "Baseline promotion metadata missing required fields: "
                + ", ".join(missing_fields)
            )
        intent_match = re.search(r"^\s*-\s*intent\s*:\s*(.+)$", metadata, flags=re.MULTILINE)
        if intent_match and intent_match.group(1).strip().strip("`").lower() != "baseline-promotion":
            checks["baseline_promotion_metadata"] = "fail"
            errors.append("Promotion intent metadata must set intent to 'baseline-promotion'.")

    status = "pass" if not errors else "fail"
    return {
        "status": status,
        "mode": mode,
        "template_type": template_type,
        "checks": checks,
        "errors": errors,
    }


def main() -> int:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

    mode = os.environ.get("PR_TEMPLATE_ENFORCEMENT_MODE", "enforce").strip().lower()
    if mode not in {"enforce", "advisory"}:
        mode = "enforce"

    event_name = os.environ.get("GITHUB_EVENT_NAME", "").strip()
    payload, payload_errors = get_event_payload()

    result: Dict[str, object] = {
        "status": "skip",
        "mode": mode,
        "event_name": event_name,
        "checks": {},
        "errors": [],
    }

    if payload_errors:
        result["status"] = "fail"
        result["errors"] = payload_errors
    else:
        pr = payload.get("pull_request", {}) if isinstance(payload, dict) else {}
        if not isinstance(pr, dict):
            result["status"] = "skip"
            result["errors"] = ["GitHub event payload has no pull_request object."]
        else:
            pr_number = pr.get("number")
            body = str(pr.get("body", "") or "")
            result.update(
                {
                    "pr_number": pr_number,
                    "head_ref": str(pr.get("head", {}).get("ref", "")),
                    "base_ref": str(pr.get("base", {}).get("ref", "")),
                }
            )
            if not body.strip():
                result["status"] = "fail"
                result["errors"] = [
                    "PR body is empty. Select a PR template and complete required sections.",
                ]
            else:
                validated = validate_pr_body(body, mode)
                result.update(validated)

    RESULT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if result.get("status") == "fail":
        print("PR template validation failed. See artifacts/policy/pr-template-validation.json for details.")
        for error in result.get("errors", []):
            print(f"- {error}")
        if mode == "enforce":
            return 1
        print("Advisory mode is enabled; continuing despite failures.")
    else:
        print("PR template validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
