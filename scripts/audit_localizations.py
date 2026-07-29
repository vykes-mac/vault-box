#!/usr/bin/env python3
"""Validate VaultBox's string catalog coverage and format placeholders."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from extract_localization_keys import source_keys


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "VaultBox/Resources/Localizable.xcstrings"
TARGET_LOCALES = ("de", "ja", "ko", "pt-BR", "es-MX", "it", "fr")
TAB_LABEL_LOCALES = ("en", *TARGET_LOCALES)
TAB_LABEL_KEYS = ("tab.vault", "tab.albums", "tab.camera", "tab.search", "tab.settings")
SEARCH_SUGGESTION_KEYS = (
    "search.suggestion.passport_number",
    "search.suggestion.contract_end_date",
    "search.suggestion.receipts_january",
    "search.suggestion.lease_expiration_date",
)
MAX_TAB_LABEL_CHARACTERS = 10
PRODUCT_NAMES = ("Ask My Vault",)
CONTEXT_TERMS = {
    "vault": {
        "de": "Tresor",
        "es-MX": "bóveda",
        "fr": "coffre",
        "it": "cassaforte",
        "ja": "保管庫",
        "ko": "보관함",
        "pt-BR": "cofre",
    },
    "decoy": {
        "de": "Täusch",
        "es-MX": "señuelo",
        "fr": "leurre",
        "it": "esca",
        "ja": "おとり",
        "ko": "위장",
        "pt-BR": "disfarce",
    },
}
FORBIDDEN_TRANSLATION_PATTERNS = {
    "de": re.compile(r"\b(?:Safe|Safebox|Kiste|Artikel)\b|\b(?:ein|das|Ihr) PIN\b"),
    "es-MX": re.compile(r"\bdecoy\b|\bartículos\b", re.IGNORECASE),
    "fr": re.compile(r"\b(?:cryptage|décrypter|crypté(?:e|es|s)?)\b", re.IGNORECASE),
    "it": re.compile(r"\bvault\b|\bcofanetto\b", re.IGNORECASE),
    "ja": re.compile(r"あなた|ウォレット|ボルト|ボウル"),
    "ko": re.compile(r"당신|귀하|PIN를|PIN로|PIN가|둥근 천장"),
    "pt-BR": re.compile(r"decóio|decofago|rolê de câmera", re.IGNORECASE),
}
PLACEHOLDER = re.compile(
    r"%(?:\d+\$)?[-+0 #']*\d*(?:\.\d+)?(?:hh|h|ll|l|z|t|j)?"
    r"[diuoxXfFeEgGaAcCsSp@]"
)


def placeholders(value: str) -> list[str]:
    return sorted(PLACEHOLDER.findall(value))


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog.get("strings", {})
    issues: list[str] = []
    extracted_keys = source_keys()
    catalog_keys = set(strings)

    for source in sorted(extracted_keys - catalog_keys):
        issues.append(f"catalog: missing source key {source!r}")

    for source in sorted(catalog_keys - extracted_keys):
        issues.append(f"catalog: stale source key {source!r}")

    for source, entry in strings.items():
        expected_placeholders = placeholders(source)
        localizations = entry.get("localizations", {})
        contextual_source = source
        for product_name in PRODUCT_NAMES:
            contextual_source = contextual_source.replace(product_name, "")

        for locale in TARGET_LOCALES:
            string_unit = localizations.get(locale, {}).get("stringUnit", {})
            value = string_unit.get("value")
            if string_unit.get("state") != "translated" or not isinstance(value, str):
                issues.append(f"{locale}: missing translation for {source!r}")
                continue

            contextual_value = value
            for product_name in PRODUCT_NAMES:
                contextual_value = contextual_value.replace(product_name, "")

            if placeholders(value) != expected_placeholders:
                issues.append(
                    f"{locale}: placeholder mismatch for {source!r}: "
                    f"{expected_placeholders} != {placeholders(value)}"
                )
            if "ZXQ" in value:
                issues.append(f"{locale}: leaked protected token in {source!r}")

            forbidden = FORBIDDEN_TRANSLATION_PATTERNS[locale].search(contextual_value)
            if forbidden:
                issues.append(
                    f"{locale}: context-free translation {forbidden.group()!r} "
                    f"in {source!r}"
                )

            for source_term, localized_terms in CONTEXT_TERMS.items():
                if re.search(rf"\b{source_term}\b", contextual_source, re.IGNORECASE):
                    expected = localized_terms[locale]
                    if expected.casefold() not in value.casefold():
                        issues.append(
                            f"{locale}: expected {expected!r} for {source_term!r} "
                            f"in {source!r}"
                        )

    for key in TAB_LABEL_KEYS:
        localizations = strings.get(key, {}).get("localizations", {})
        for locale in TAB_LABEL_LOCALES:
            value = localizations.get(locale, {}).get("stringUnit", {}).get("value")
            if not isinstance(value, str):
                issues.append(f"{locale}: missing compact tab label for {key!r}")
            elif len(value) > MAX_TAB_LABEL_CHARACTERS:
                issues.append(
                    f"{locale}: tab label for {key!r} is too long: "
                    f"{len(value)} > {MAX_TAB_LABEL_CHARACTERS} characters"
                )

    for key in SEARCH_SUGGESTION_KEYS:
        localizations = strings.get(key, {}).get("localizations", {})
        for locale in ("en", *TARGET_LOCALES):
            value = localizations.get(locale, {}).get("stringUnit", {}).get("value")
            if not isinstance(value, str) or not value.strip():
                issues.append(f"{locale}: missing Smart Search suggestion for {key!r}")

    if issues:
        print("\n".join(issues))
        print(f"Localization audit failed with {len(issues)} issue(s).")
        return 1

    localized_entries = len(strings) * len(TARGET_LOCALES)
    print(
        f"Localization audit passed: {len(strings)} source keys, "
        f"{localized_entries} translated entries, 0 issues."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
