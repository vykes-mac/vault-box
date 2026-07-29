#!/usr/bin/env python3
"""Build the source-language string catalog from VaultBox's SwiftUI sources."""

from __future__ import annotations

import ast
import json
import re
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "VaultBox/Resources/Localizable.xcstrings"

STRING_LITERAL = re.compile(r'"((?:\\.|[^"\\])*)"')
INTERPOLATION = re.compile(r"\\\(")
LOCALIZABLE_LITERAL = re.compile(
    r"(?:(?:Text|Button|Label|ProgressView|ContentUnavailableView|LabeledContent|"
    r"navigationTitle|alert|confirmationDialog|Toggle|Picker|TextField|SecureField|"
    r"Section|Menu|accessibilityLabel|accessibilityHint)\(\s*"
    r"|String\(\s*localized:\s*)\"((?:\\.|[^\"\\])*)\"",
    re.MULTILINE,
)

EXCLUDED_PREFIXES = (
    "http://",
    "https://",
    "music://",
    "sms://",
    "file://",
    "com.",
    "group.",
    "icloud.",
    "INSERT ",
    "SELECT ",
    "DELETE ",
    "CREATE ",
    "HTTP/",
)


def decode_swift_unicode_escapes(contents: str) -> str:
    return re.sub(
        r"\\u\{([0-9A-Fa-f]+)\}",
        lambda match: chr(int(match.group(1), 16)),
        contents,
    )


def decode_swift_literal(contents: str) -> str | None:
    if INTERPOLATION.search(contents):
        return None
    contents = decode_swift_unicode_escapes(contents)
    try:
        return ast.literal_eval(f'"{contents}"')
    except (SyntaxError, ValueError):
        return contents.replace(r'\"', '"').replace(r'\\', '\\')


def looks_user_facing(value: str) -> bool:
    stripped = value.strip()
    if not stripped or not any(character.isalpha() for character in stripped):
        return False
    if len(stripped) > 300 or any(marker in stripped for marker in ("<", "{", "\\r")):
        return False
    if stripped.startswith(EXCLUDED_PREFIXES):
        return False
    if stripped.startswith(("%K", "-----", ")", ":")):
        return False
    if "@" in stripped and " " not in stripped:
        return False
    if "/" in stripped and " " not in stripped:
        return False
    if stripped.startswith("_") or stripped.endswith((".fill", ".circle", ".badge")):
        return False
    allowed_lowercase_prefixes = ("iCloud", "iOS")
    if not (stripped[0].isupper() or stripped[0].isdigit() or stripped[0] in "'\"•") \
            and not stripped.startswith(allowed_lowercase_prefixes):
        return False
    return True


def source_keys() -> set[str]:
    keys: set[str] = set()
    for source in sorted((ROOT / "VaultBox").rglob("*.swift")):
        contents = source.read_text(encoding="utf-8")
        for match in LOCALIZABLE_LITERAL.finditer(contents):
            value = decode_swift_literal(match.group(1))
            if value is not None:
                keys.add(value)
    swift_sources = [str(path) for path in sorted((ROOT / "VaultBox").rglob("*.swift"))]
    with tempfile.TemporaryDirectory() as output_directory:
        result = subprocess.run(
            ["xcrun", "extractLocStrings", "-SwiftUI", "-u", "-o", output_directory, *swift_sources],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "extractLocStrings failed")
        extracted = Path(output_directory) / "Localizable.strings"
        if extracted.exists():
            raw_contents = extracted.read_bytes()
            encoding = "utf-16" if raw_contents.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8"
            contents = raw_contents.decode(encoding)
            for match in re.finditer(r'^"((?:\\.|[^"\\])*)"\s*=', contents, re.MULTILINE):
                raw_key = match.group(1)
                key = raw_key.replace(r'\n', '\n').replace(r'\"', '"').replace(r'\\', '\\')
                key = decode_swift_unicode_escapes(key)
                keys.add(key)
    return keys


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    existing = catalog.setdefault("strings", {})
    requested_keys = source_keys()
    existing = {key: existing.get(key, {}) for key in sorted(requested_keys)}
    catalog["strings"] = existing
    CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Catalog contains {len(existing)} source keys")


if __name__ == "__main__":
    main()
