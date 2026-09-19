#!/usr/bin/env bash
# Static-check every .qml file in this shell with qmllint.
#
# Files import each other as `qs.shared`, `qs.services` and so on, a module
# Quickshell synthesises at runtime with no qmldir on disk — so qmllint alone
# resolves none of it and every cross-file type comes back unknown. This builds
# a throwaway shim tree spelling out the same layout, points qmllint at it with
# -I, and deletes it afterwards.
#
# Quiet on success. Unfixable findings are suppressed individually with a
# reason (see SUPPRESSED), never by category, so anything new still fails.
#
# Usage: scripts/lint.sh [--all] [files...]
#          --all    also list the suppressed findings, with reasons
#        (default: every .qml file in the repo)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
qmllint="$(command -v qmllint || echo /usr/lib64/qt6/bin/qmllint)"
[ -x "$qmllint" ] || { echo "lint: qmllint not found" >&2; exit 127; }

show_all=0
if [ "${1:-}" = "--all" ]; then
    show_all=1
    shift
fi

shim="$(mktemp -d)"
trap 'rm -rf "$shim"' EXIT

# One qmldir per source directory, mirroring `qs.<dir>.<subdir>`. A file whose
# first line is `pragma Singleton` has to be declared `singleton` here too, or
# qmllint reads it as a type rather than an instance and reports every property
# on it as missing.
python3 - "$repo" "$shim" <<'SHIM'
import pathlib, sys
repo, out = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2])
for d in [repo] + [p for p in repo.rglob("*") if p.is_dir() and ".git" not in p.parts]:
    qmls = sorted(d.glob("*.qml"))
    if not qmls:
        continue
    rel = d.relative_to(repo)
    target = out / "qs" / rel
    target.mkdir(parents=True, exist_ok=True)
    lines = ["module qs" + ("." + ".".join(rel.parts) if rel.parts else "")]
    for q in qmls:
        singleton = q.read_text().startswith("pragma Singleton")
        lines.append(("singleton " if singleton else "") + q.stem + " 1.0 " + q.name)
        (target / q.name).symlink_to(q)
    (target / "qmldir").write_text("\n".join(lines) + "\n")
SHIM

if [ "$#" -gt 0 ]; then
    files=("$@")
else
    mapfile -t files < <(find "$repo" -name '*.qml' -not -path '*/.git/*' | sort)
fi

report="$("$qmllint" --json - -I "$shim" -I /usr/lib64/qt6/qml "${files[@]}" 2>/dev/null || true)"

# The report goes through the environment: stdin already carries this filter's
# own source, via the heredoc.
REPO="$repo" SHOW_ALL="$show_all" REPORT="$report" python3 - <<'FILTER'
import json, os, sys

repo = os.environ["REPO"].rstrip("/") + "/"
show_all = os.environ["SHOW_ALL"] == "1"

# Known-unfixable findings, suppressed individually rather than by category.
# Every one is either a gap in Quickshell's own qmltypes or a place this shell
# duck-types on purpose. Entries: (path suffix or "*", id, message prefix, why).
SUPPRESSED = [
    # --- Quickshell qmltypes gaps -------------------------------------------
    ("*", "uncreatable-type", "Type PanelWindow is not creatable.",
     "quickshell-window.qmltypes declares PanelWindowInterface isCreatable:false; "
     "Quickshell substitutes the real backend at runtime"),
    ("*", "unqualified", "unknown grouped property scope margins.",
     "PanelWindow.margins is type Margins, a gadget Quickshell does not export"),
    ("*", "unresolved-type", "Type margins is used but it is not resolved",
     "same Margins gadget"),
    ("*", "missing-type", 'No type found for property "edges"',
     "Edges flag enum is not exported"),
    ("*", "missing-type", 'No type found for property "gravity"',
     "Edges flag enum is not exported"),
    ("*", "missing-type", 'No type found for property "adjustment"',
     "PopupAdjustment flag enum is not exported"),
    ("*", "unresolved-type", 'Type "PopupAnchor" of property "anchor" not found',
     "PopupAnchor is not exported declaratively"),
    ("*", "signal-handler-parameters", "Type QProcess::ExitStatus",
     "Process.exited's QProcess::ExitStatus parameter is not exported"),
    ("*", "unresolved-type",
     'Type "QList<qs::service::notifications::NotificationAction*>"',
     "NotificationAction list type is not exported"),

    # --- deliberate duck-typing in this shell -------------------------------
    ("shared/ModuleLoader.qml", "missing-property",
     'Member "contentVisible" not found on type "QObject"',
     "Loader.item is statically QObject and this Loader is deliberately "
     "heterogeneous: BarModule and Privacy declare contentVisible, Workspaces "
     "does not, hence the `=== undefined` probe. Typing it would mean forcing "
     "every placeable module onto one base class, which Workspaces (a Rectangle "
     "owning its own SpringGroup) should not be"),
    ("shared/ModuleLoader.qml", "missing-property",
     'Member "textColor" not found on type "QObject"',
     "same probe: the group's text colour is handed only to modules that "
     "declare it (BarModule); Workspaces and Privacy colour themselves"),
    ("shared/notifications/NotificationPopupWindow.qml", "missing-property",
     'Member "naturalWidth" not found on type "QQuickItem"',
     "Repeater.itemAt() is statically QQuickItem; naturalWidth is an alias on "
     "the inline delegate"),
]


def suppression_for(path, warning):
    for suffix, wid, prefix, reason in SUPPRESSED:
        if suffix != "*" and not path.endswith(suffix):
            continue
        if warning.get("id") == wid and warning.get("message", "").startswith(prefix):
            return reason
    return None


try:
    report = json.loads(os.environ["REPORT"])
except json.JSONDecodeError:
    print("lint: qmllint produced no parseable output", file=sys.stderr)
    sys.exit(2)

actionable, suppressed = [], []
for entry in report.get("files", []):
    name = entry.get("filename", "?")
    name = name[len(repo):] if name.startswith(repo) else name
    for w in entry.get("warnings", []):
        where = "%s:%s:%s" % (name, w.get("line"), w.get("column"))
        reason = suppression_for(name, w)
        if reason:
            suppressed.append((where, w, reason))
        else:
            actionable.append("%s: %s [%s]" % (where, w.get("message"), w.get("id")))

if show_all:
    for where, w, reason in suppressed:
        print("  known %s: %s [%s]" % (where, w.get("message"), w.get("id")))
        print("        reason: %s" % reason)
    print()

for line in actionable:
    print(line)

if actionable:
    print("\nlint: %d finding(s)" % len(actionable), file=sys.stderr)
    sys.exit(1)

hint = "" if show_all else " (%d known-unfixable suppressed; --all to list them)" % len(suppressed)
print("lint: clean%s" % hint)
FILTER
