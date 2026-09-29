#!/usr/bin/env python3
"""Require fresh, executed Android Compose regressions, with no skips."""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path)
parser.add_argument("--since", required=True, type=float)
args = parser.parse_args()
reports = sorted(args.directory.glob("TEST-*.xml"))
if not reports:
    parser.error("No Android Compose JUnit reports were produced")

cases = []
for report in reports:
    if report.stat().st_mtime < args.since:
        parser.error(f"Stale Android Compose report: {report.name}")
    cases.extend(ET.parse(report).getroot().iter("testcase"))

required = {
    "testContactSectionsUseDisjointRowIdentities",
    "testFlattenedSectionRowsUseStableIdentitiesAndContactNavigates",
}
executed = {case.attrib["name"].split("$", 1)[0] for case in cases}
if missing := required - executed:
    parser.error("Compose regressions did not execute: " + ", ".join(sorted(missing)))
for case in cases:
    if any(child.tag in {"failure", "error", "skipped"} for child in case):
        parser.error("Compose regression failed or skipped: " + case.attrib["name"])
print(f"Android Compose: {len(cases)} tests executed, zero failures or skips")
