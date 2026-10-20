# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""Anonymize a MyoDish recording (.mdd, _log.log, _labels.csv, LabChart .mat of a parallel EP recording) for sharing.

    python anonymize_recording.py <recording.mdd> <new_name> [--outdir DIR] [--date 2000-01-01] [--mat FILE.mat]
                                  [--initials AB,CD] [--map FILE.json] [--show]

What is changed (the .mdd data file is only copied under the new name; its time of last change is shifted by the same
number of days):
  - systemTime of all log lines: shifted by a whole number of days so that the first entry falls on --date
    (time of day and all time differences are kept; dataLogTime, i.e. the time in the .mdd file, is unchanged; also
    time stamps without leading zeros, '1999 12 24 8:48:22:399', software before 2.0.7717).
  - dates in comments ('Started parallel recording: 01/Jan/2000 12:00:00'): same shift; software build date removed.
  - Windows paths (user names, folders with dates or sample IDs): reduced to the file name; the recording's own
    file names are replaced by <new_name>.mdd / <new_name>_log.log.
  - software version (programInfo, ProgramVersion): build number removed ('Version 2.0.9708.42745' -> 'Version 2.0';
    it encodes the build date). Builds 2.0.7713-2.0.7970, which wrote 12-hour time stamps, become '2.0.7717', so that
    MyoDishAnalysis still corrects AM/PM.
  - initials given with --initials AB,CD: 'AB: comment' -> 'P1: comment', '_AB' in protocol (schedule file) names ->
    '_P1' (pseudonyms of persons, the same as for 'by' in structured lines and analyst / owner in _labels.csv).
  - connectedDevice (serial number of the USB adapter): replaced by a generic text.
  - structured log lines (software 2.1 and later; the value is one JSON object): changed by field name (and event
    where a name means different things), in every event:
      pc -> 'PC', winUser -> 'user', pnp -> 'USB serial device', software -> major.minor ('2.1');
      controllerId and ftdiSerial -> 'controller1', 'controller2', ...; chamberId -> 'chamber1', ...;
      persons: by, initials, user, owner, removedBy and previous (event user) -> 'P1', 'P2', ... ('auto' and null
      kept); name of the event user (full name of a person) -> the pseudonym of that person;
      sampleId -> 'S1', ... (as sampleID of _labels.csv); sliceId -> the sample pseudonym inside the slice ID;
      file, previousFile, path, scheduleFile, parentFile, preset -> file name (own name -> <new_name>; '_AB' of
      --initials -> '_P1'); folders (folder, target, previousTarget, to) -> 'folder1', 'folder2', ...;
      times cultureStart, installTime, removeTime, time -> shifted by the same number of days (time of day and offset
      kept); protocol names (name of protocolRun and scheduleRun) and free texts (comment, text, destination, and
      reason of slice_remove and backup_failed) -> like comments (paths, own name, --initials, dates);
      client (sync program) -> 'sync client', evidence -> 'removed'.
    All other fields are kept (IDs that link events, time zone, port, labels of the slices such as species, tissue,
    groups, treatment, medium, substance, numbers exactly as written); the free texts and labels are listed by --show.
    The line stays one line of pure ASCII JSON (';' as \\u003b). A structured line that cannot be read (cut off after
    a crash) is kept unchanged and reported.
  - <name>_labels.csv (if present) -> <new_name>_labels.csv: sampleID -> 'S1', 'S2', ..., the sample ID inside sliceID
    ('<sampleID>_S<setup>C<channel>') replaced by the same pseudonym, analyst and owner -> pseudonyms of persons (the
    same as 'by' in the log), cultureStart shifted by the same number of days, comment as the comments of the log.
  - LabChart .mat (--mat): blocktimes shifted by the same number of days; comtext dates shifted.
--map FILE.json: pseudonyms read before and written after the run, so that the recordings of one study get the same
pseudonyms. The map contains the original values: keep it, do not share it.
Final check: the output files are searched for every original value that was replaced (PC and user name, serial
numbers, initials, names, sample, slice and chamber IDs, folders, the original file name) and for the dates of the
recording and of the shifted times of structured lines (forms '1999 12 24', '24.12.1999', '24/Dec/1999',
'1999-12-24'). If one is still there (e.g. inside a free-text
comment), the output files are deleted and the tool stops with an error naming the line.
Line order, codes, channels and all numbers used by the analysis are kept, so MyoDishAnalysis gives the same
results (clock times shifted by the same number of days). Check the free-text comments yourself (--show) before
sharing: names or other identifying words inside comments cannot be recognized automatically.

TS 2026-10-07 (structured log lines, _labels.csv, --map, final check, time stamps without leading zeros, 12-hour
builds, file time: 2026-10-17; fields of the slice, protocol, schedule, doc, backup and folder events: 2026-10-20)
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import json
import os
import re
import shutil
import sys

# systemTime; software before 2.0.7717 (2020/21) wrote it without leading zeros ('1999 12 24 8:48:22:399')
_SYS = re.compile(r"^(\s*)(\d{4}) (\d{1,2}) (\d{1,2}) (\d{1,2}:\d{1,2}:\d{1,2}(?::\d+)?)(.*)$")
_STAMP = re.compile(r"(?<!\d)\d{4} \d{1,2} \d{1,2} \d{1,2}:\d{1,2}:\d{1,2}(?::\d+)?")  # systemTime inside a text
_FRAG = re.compile(r"(?:[^\\;\r\n]*\\)+")  # directory part of a path cut off at the start of a broken line
_H12 = (7713, 7970)   # software 2.0.7713-2.0.7970 wrote 12-hour time stamps (clock_time.py of MyoDishAnalysis)
_PATH = re.compile(r"(?:[A-Za-z]:\\|\\\\)(?:[^\\\r\n]*\\)*")  # directory part of a Windows path (drive or network path)
_MONTHS = {"jan": 1, "feb": 2, "mar": 3, "mrz": 3, "mär": 3, "apr": 4, "may": 5, "mai": 5, "jun": 6, "jul": 7,
           "aug": 8, "sep": 9, "oct": 10, "okt": 10, "nov": 11, "dec": 12, "dez": 12}
_MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
_DATE_TXT = re.compile(r"(\d{1,2})([./])([A-Za-zä]{3})\2(\d{4})")      # 01/Mar/2000, 01.Mrz.2000
_DATE_NUM = re.compile(r"(\d{1,2})([./])(\d{1,2})\2(\d{4})")           # 31.01.2000, 18/03/2000
_ISO_DAY = re.compile(r"^(\s*)(\d{4})-(\d{2})-(\d{2})(?=[T ]|$)")     # 2000-01-31 08:30, 2000-01-31T08:30:00+01:00

# structured log lines: fields by name; names that mean different things in different events (name, reason,
# previous) by event as well (fields of the control software, notes of its development of 2026-10-18 and 2026-10-20)
_FIXED = {"pc": "PC", "winUser": "user", "pnp": "USB serial device"}
_GENERIC = {"client": "sync client", "evidence": "removed"}   # sync program, how a synchronised folder was recognized
_CONTROLLER = ("controllerId", "ftdiSerial")
_PERSON = ("by", "initials", "user", "owner", "removedBy")
_PATHS = ("file", "previousFile", "path", "scheduleFile", "parentFile", "preset")
_FOLDERS = ("folder", "target", "previousTarget", "to")
_TIMES = ("cultureStart", "installTime", "removeTime", "time")
_FREE = ("comment", "text", "destination")
_FREE_REASON = ("slice_remove", "backup_failed")             # events whose reason is free text
_NAME_TEXT = ("protocolRun", "scheduleRun")                   # codes whose name is a protocol name
_LABELS = ("species", "tissue", "sampleGroup", "sliceGroup", "treatment", "medium", "substance", "vehicle")
_KEEP_PERSON = ("auto",)
_KEY_STR = re.compile(r'"(%s)"\s*:\s*"((?:[^"\\]|\\.)*)"'
                      % "|".join(tuple(_FIXED) + ("software", "sampleId", "sliceId", "chamberId", "name")
                                 + _CONTROLLER + _PERSON))
_SUBSTRING = ("controller", "pnp", "software", "file name", "folder")  # searched anywhere by the final check


class AnonymizationError(RuntimeError):
    """original values are still in the output files (the output files were deleted)."""


class Pseudonyms:
    """consistent pseudonyms per value ('controller1', 'P1', 'S1', 'slice1'), the same in all files of a run and, with
    a map file (--map), in several runs. originals: original value -> kind of every value replaced in this run (for
    the final check); unreadable: line numbers of structured log lines that could not be read."""
    PREFIX = {"controller": "controller", "person": "P", "sample": "S", "slice": "slice", "chamber": "chamber",
              "folder": "folder"}

    def __init__(self, map_file=None):
        self.map = {k: {} for k in self.PREFIX}
        if map_file and os.path.isfile(map_file):
            with open(map_file, encoding="utf-8") as fh:
                d = json.load(fh)
            for k in self.PREFIX:
                self.map[k].update({str(a): str(b) for a, b in (d.get(k) or {}).items()})
        self.originals = {}
        self.unreadable = []
        self.dates = set()      # original dates of the shifted times of structured lines (for the final check)
        self.texts = []         # free texts and labels of structured lines (for --show)

    def get(self, kind, value):
        m = self.map[kind]
        if value not in m:
            pre = self.PREFIX[kind]
            used = [int(x[len(pre):]) for x in m.values() if x.startswith(pre) and x[len(pre):].isdigit()]
            m[value] = "%s%d" % (pre, max(used, default=0) + 1)
        self.originals.setdefault(value, kind)
        return m[value]

    def replaced(self, value, kind):
        if value:
            self.originals.setdefault(value, kind)

    def save(self, map_file):
        d = {"note": "pseudonyms of anonymize_recording.py; contains the original values: do not share"}
        d.update(self.map)
        with open(map_file, "w", encoding="utf-8") as fh:
            json.dump(d, fh, indent=1, ensure_ascii=False)
            fh.write("\n")


def read_text(path):
    b = open(path, "rb").read()
    bom = b[:2] == b"\xff\xfe"
    if bom or (len(b) >= 4 and b[1] == 0 and b[3] == 0):
        return b[2:].decode("utf-16-le") if bom else b.decode("utf-16-le"), "utf-16-le", bom
    return b.decode("utf-8", errors="replace"), "utf-8", False


def write_text(path, txt, enc, bom):
    with open(path, "wb") as fh:
        if bom:
            fh.write(b"\xff\xfe")
        fh.write(txt.encode(enc))


def _read_csv_text(path):
    with open(path, "rb") as fh:
        b = fh.read()
    if b[:3] == b"\xef\xbb\xbf":
        return b[3:].decode("utf-8"), "utf-8", True
    try:
        return b.decode("utf-8"), "utf-8", False
    except UnicodeDecodeError:
        return b.decode("cp1252"), "cp1252", False


def _write_csv_text(path, txt, enc, bom):
    with open(path, "wb") as fh:
        fh.write((b"\xef\xbb\xbf" if bom else b"") + txt.encode(enc))


def _shift_system_time(s, days):
    """systemTime shifted by days, written in the same form (with or without leading zeros)"""
    m = _SYS.match(s)
    try:
        d = dt.date(int(m.group(2)), int(m.group(3)), int(m.group(4))) + dt.timedelta(days=days)
    except (AttributeError, ValueError):
        return s
    w = "%02d" if len(m.group(3)) == 2 else "%d", "%02d" if len(m.group(4)) == 2 else "%d"
    return ("%s%04d " + w[0] + " " + w[1] + " %s%s") % (m.group(1), d.year, d.month, d.day, m.group(5), m.group(6))


def _shift_stamps(s, days):
    """time stamps of log lines inside a text (lines glued together after an interrupted write) shifted by days"""
    return _STAMP.sub(lambda m: _shift_system_time(m.group(0), days), s)


def _version(v):
    """'2.0.9708.42745' -> '2.0' (the build number encodes the build date); a build that wrote 12-hour time stamps
    (2.0.7713-2.0.7970) -> '2.0.7717', so that MyoDishAnalysis still corrects AM/PM"""
    m = re.match(r"(\d+)\.(\d+)(?:\.(\d+))?", v)
    if m.group(1, 2) == ("2", "0") and m.group(3) and _H12[0] <= int(m.group(3)) <= _H12[1]:
        return "2.0.7717"
    return m.group(1) + "." + m.group(2)


def _dates_regex(dates):
    """the dates in the forms of the log: systemTime ('1999 12 24', '2000 1 1'), comments ('24.12.1999',
    '24/Dec/1999', '24.Dez.1999'), ISO ('1999-12-24')"""
    alts = []
    for i, d in enumerate(sorted(dates)):
        mon = "|".join(re.escape(k) for k, v in _MONTHS.items() if v == d.month)
        alts += [r"(?<!\d)%04d +0?%d +0?%d(?!\d)" % (d.year, d.month, d.day),
                 r"(?<!\d)0?%d(?P<a%d>[./])0?%d(?P=a%d)%04d(?!\d)" % (d.day, i, d.month, i, d.year),
                 r"(?<!\d)0?%d(?P<b%d>[./])(?:%s)[a-zä]*(?P=b%d)%04d(?!\d)" % (d.day, i, mon, i, d.year),
                 r"(?<!\d)%04d-%02d-%02d(?!\d)" % (d.year, d.month, d.day)]
    return re.compile("|".join(alts), re.IGNORECASE) if alts else None


def _log_dates(lines):
    """dates of the systemTime of the log lines, in the order of the lines (each once)"""
    out = {}
    for ln in lines:
        m = _SYS.match(ln.split(";", 1)[0])
        if m:
            try:
                out.setdefault(dt.date(int(m.group(2)), int(m.group(3)), int(m.group(4))), None)
            except ValueError:
                pass
    return list(out)


def first_date(lines):
    d = _log_dates(lines[:1000]) or _log_dates(lines)
    return d[0] if d else None


def _shift_text_dates(s, days):
    def txt(m):
        mon = _MONTHS.get(m.group(3).lower())
        if mon is None:
            return m.group(0)
        d = dt.date(int(m.group(4)), mon, int(m.group(1))) + dt.timedelta(days=days)
        return "%02d%s%s%s%04d" % (d.day, m.group(2), _MON[d.month - 1], m.group(2), d.year)

    def num(m):
        try:
            d = dt.date(int(m.group(4)), int(m.group(3)), int(m.group(1))) + dt.timedelta(days=days)
        except ValueError:
            return m.group(0)
        return "%02d%s%02d%s%04d" % (d.day, m.group(2), d.month, m.group(2), d.year)

    return _DATE_NUM.sub(num, _DATE_TXT.sub(txt, s))


def _shift_iso(s, days):
    """an ISO date ('2000-01-31 08:30', '2000-01-31T08:30:00+01:00') shifted by days, time of day and offset kept;
    other date forms as in comments."""
    m = _ISO_DAY.match(s)
    if not m:
        return _shift_text_dates(s, days)
    try:
        d = dt.date(int(m.group(2)), int(m.group(3)), int(m.group(4))) + dt.timedelta(days=days)
    except ValueError:
        return s
    return "%s%04d-%02d-%02d%s" % (m.group(1), d.year, d.month, d.day, s[m.end():])


def _initials_patterns(initials):
    ini = "|".join(re.escape(x) for x in initials if x)
    if not ini:
        return None, None
    return re.compile(r"^(\s*)(%s)(\s*:\s*)" % ini), re.compile(r"_(%s)(?=[_.\s)]|$)" % ini)


def _replace_initials(v, pre, suf, names, comment):
    """initials -> pseudonyms of persons: 'AB: text' (comments) -> 'P1: text', '_AB' -> '_P1'"""
    if comment:
        v = pre.sub(lambda m: m.group(1) + names.get("person", m.group(2)) + m.group(3), v)
    return suf.sub(lambda m: "_" + names.get("person", m.group(1)), v)


def anonymize_log_text(txt, old_stem, new_stem, days, initials=(), names=None):
    """returns the anonymized text and the list of comment texts (for review). names: Pseudonyms of the run (used for
    the structured lines; a new one if not given)."""
    if names is None:
        names = Pseudonyms()
    pre, suf = _initials_patterns(initials)
    nl = "\r\n" if "\r\n" in txt else "\n"
    lines = txt.split(nl)
    out, comments = [], []
    for i, ln in enumerate(lines, start=1):
        f = ln.split(";", 4)
        if len(f) < 5:
            # rest of a line broken by an interrupted write (or of a multi-line message): paths, own file name,
            # initials, dates as in the values (MyoDishAnalysis does not read such lines)
            v = _FRAG.sub("", _PATH.sub("", ln)).replace(old_stem, new_stem)
            if pre is not None:
                v = _replace_initials(v, pre, suf, names, False)
            out.append(_shift_stamps(_shift_text_dates(v, days), days))
            continue
        if _SYS.match(f[0]):
            f[0] = _shift_system_time(f[0], days)
        else:
            mt = _STAMP.search(f[0])
            if mt:   # rest of a broken line glued to the next entry: replaced (its time is not read anyway)
                f[0] = "(cut) " + _shift_system_time(f[0][mt.start():], days)
        if f[4].lstrip().startswith("{"):             # structured line (JSON; old lines never start with '{')
            f[4] = _json_value(f[4], i, _Ctx(old_stem, new_stem, names, days, pre, suf, f[3].strip()))
            out.append(";".join(f))
            continue
        code, v = f[3].strip().lower(), f[4]
        v = _PATH.sub("", v)                         # paths -> file names
        v = v.replace(old_stem, new_stem)            # own file names
        if code == "programinfo" and v.strip().lower().startswith("version"):
            mv = re.match(r"(\s*[Vv]ersion\s+)(\d+\.\d+(?:\.\d+)?)", v)
            v = (mv.group(1) + _version(mv.group(2))) if mv else "Version"
        elif code == "programversion":               # 2021-2022: 'ProgramVersion;2.0.7769.26061'
            mv = re.match(r"(\s*)(\d+\.\d+(?:\.\d+)?)", v)
            v = (mv.group(1) + _version(mv.group(2))) if mv else v
        elif code == "programinfo" and v.strip().lower().startswith("date"):
            v = "Date"                               # build date (would allow to undo the date shift)
        elif code == "connecteddevice":
            v = "USB serial device"
        if pre is not None:
            v = _replace_initials(v, pre, suf, names, code == "comment")
        v = _shift_stamps(_shift_text_dates(v, days), days)
        f[4] = v
        if code == "comment":
            comments.append(v)
        out.append(";".join(f))
    return nl.join(out), comments


class _Raw(str):
    """a JSON number exactly as written in the log"""


class _Obj(list):
    """a JSON object as (name, value) pairs (order and repeated names kept)"""


def _loads(s):
    return json.loads(s, object_pairs_hook=_Obj, parse_int=_Raw, parse_float=_Raw, parse_constant=_Raw)


def _dumps(o):
    if isinstance(o, _Raw):
        return str(o)
    if isinstance(o, _Obj):
        return "{" + ",".join(json.dumps(k) + ":" + _dumps(v) for k, v in o) + "}"
    if isinstance(o, list):
        return "[" + ",".join(_dumps(x) for x in o) + "]"
    return json.dumps(o)                             # string (ASCII, \uXXXX), true, false, null


def _software(v):
    m = re.match(r"\s*(\d+)\.(\d+)", v)
    return m.group(1) + "." + m.group(2) if m else v.split(".")[0]


class _Ctx:
    """what a structured line needs: names of the recording, pseudonyms, days of the shift, --initials patterns, code"""

    def __init__(self, old_stem, new_stem, names, days, pre, suf, code):
        self.old, self.new, self.names, self.days, self.pre, self.suf, self.code = \
            old_stem, new_stem, names, days, pre, suf, code


def _file_name(v, c):
    """a path or file name -> file name; own name -> new name; '_AB' of --initials -> '_P1'"""
    v = re.split(r"[\\/]", v)[-1].replace(c.old, c.new)
    return v if c.pre is None else _replace_initials(v, c.pre, c.suf, c.names, False)


def _free_text(v, c, comment=True):
    """a free text or protocol name, like the comments of the old lines: paths -> file names, own name, --initials,
    dates shifted"""
    v = _PATH.sub("", v).replace(c.old, c.new)
    if c.pre is not None:
        v = _replace_initials(v, c.pre, c.suf, c.names, comment)
    return _shift_stamps(_shift_text_dates(v, c.days), c.days)


def _iso_time(v, c):
    m = _ISO_DAY.match(v)
    if m:
        try:
            c.names.dates.add(dt.date(int(m.group(2)), int(m.group(3)), int(m.group(4))))
        except ValueError:
            pass
    return _shift_iso(v, c.days)


def _json_field(key, v, c, ev, obj):
    """the anonymized value of field key (event ev, obj = the object that holds it, for the sample of a slice ID)"""
    if isinstance(v, _Obj):
        return _json_object(v, c, ev)
    if isinstance(v, list):
        return [_json_field(key, x, c, ev, obj) for x in v]
    if not isinstance(v, str) or isinstance(v, _Raw) or v == "":
        return v                                     # numbers, true, false, null, ''
    names = c.names
    if key in _FIXED:
        if v != _FIXED[key]:
            names.replaced(v, key)
        return _FIXED[key]
    if key in _GENERIC:
        return _GENERIC[key]
    if key == "software":
        s = _software(v)
        if s != v:
            names.replaced(v, key)
        return s
    if key in _CONTROLLER:
        return names.get("controller", v)
    if key in _PERSON or (key == "previous" and ev == "user"):
        return v if v in _KEEP_PERSON else names.get("person", v)
    if key == "name" and ev == "user":               # full name of a person: the pseudonym of that person
        who = dict((k, x) for k, x in obj if k in ("initials", "by"))
        ini = who.get("initials") or who.get("by")
        names.replaced(v, "person")
        return names.get("person", ini) if isinstance(ini, str) and ini and not isinstance(ini, _Raw) \
            else names.get("person", v)
    if key == "sampleId":
        return names.get("sample", v.strip())
    if key == "sliceId":
        sample = dict(obj).get("sampleId")
        return _slice_id(v, sample if isinstance(sample, str) and not isinstance(sample, _Raw) else "", names)
    if key == "chamberId":
        return names.get("chamber", v)
    if key in _FOLDERS:
        return names.get("folder", v)
    if key in _PATHS:
        return _file_name(v, c)
    if key in _TIMES:
        return _iso_time(v, c)
    if key in _FREE or (key == "reason" and ev in _FREE_REASON):
        v = _free_text(v, c)
        names.texts.append("%s %s: %s" % (ev or c.code, key, v))
        return v
    if key == "name" and c.code in _NAME_TEXT:
        v = _free_text(v, c, False)
        names.texts.append("%s name: %s" % (ev or c.code, v))
        return v
    if key in _LABELS:
        names.texts.append("%s %s: %s" % (ev or c.code, key, v))
    return v


def _json_object(o, c, ev=None):
    ev = next((x for k, x in o if k == "event" and isinstance(x, str)), ev)
    return _Obj((k, _json_field(k, x, c, ev, o)) for k, x in o)


def _json_value(v, line, c):
    """the anonymized value of a structured line. A value that cannot be read is kept unchanged (line number in
    names.unreadable; its identifying values in names.originals, so that the final check finds them)."""
    names = c.names
    try:
        obj = _loads(v.strip())
    except (ValueError, RecursionError):
        names.unreadable.append(line)
        for k, raw in _KEY_STR.findall(v):
            try:
                x = json.loads('"%s"' % raw)
            except ValueError:
                x = raw
            if (k in _FIXED and x != _FIXED[k]) or (k == "software" and _software(x) != x):
                names.replaced(x, k)
            elif k in _CONTROLLER:
                names.replaced(x, "controller")
            elif k in _PERSON and x not in _KEEP_PERSON:
                names.replaced(x, "person")
            elif k in ("sampleId", "sliceId", "chamberId") and x:
                names.replaced(x, {"sampleId": "sample", "sliceId": "slice", "chamberId": "chamber"}[k])
            elif k == "name" and x and re.search(r'"event"\s*:\s*"user"', v):   # full name of a person
                names.replaced(x, "person")
        return v
    new = _dumps(_json_field(None, obj, c, None, None)).replace(";", "\\u003b")
    if not new.isascii() or any(ch in new for ch in ";\r\n\t"):
        raise ValueError("structured log line %d cannot be written as one line of ASCII JSON" % line)
    return v[:len(v) - len(v.lstrip())] + new + v[len(v.rstrip()):]


def _cell(r, col, name):
    j = col.get(name)
    return r[j] if j is not None and j < len(r) else ""


def _person(s, names):
    t = s.strip()
    if not t or t in _KEEP_PERSON:
        return s
    return s[:len(s) - len(s.lstrip())] + names.get("person", t) + s[len(s.rstrip()):]


def _slice_id(s, sample, names):
    """the slice ID ('<sampleID>_S<setup>C<channel>') with the pseudonym of its sample"""
    s, sample = s.strip(), sample.strip()
    if sample and s.startswith(sample):
        new = names.get("sample", sample) + s[len(sample):]
    else:
        m = re.match(r"^(.+)(_S\d+C\d+)$", s)
        new = names.get("sample", m.group(1)) + m.group(2) if m else names.get("slice", s)
    names.replaced(s, "slice")
    return new


def anonymize_labels_text(txt, old_stem, new_stem, days, initials=(), names=None):
    """returns the anonymized text of a _labels.csv file and its comments (for review): sampleID -> pseudonym, the
    sample ID inside sliceID -> the same pseudonym, analyst and owner -> pseudonyms of persons, cultureStart shifted by
    days, comment as the comments of the log. Other columns are kept."""
    if names is None:
        names = Pseudonyms()
    pre, suf = _initials_patterns(initials)
    nl = "\r\n" if "\r\n" in txt else "\n"
    rows = list(csv.reader(io.StringIO(txt)))
    if not rows:
        return txt, []
    col = {h.strip().lower(): j for j, h in enumerate(rows[0])}
    comments = []
    for r in rows[1:]:
        sample = _cell(r, col, "sampleid")
        if sample.strip():
            r[col["sampleid"]] = names.get("sample", sample.strip())
        if _cell(r, col, "sliceid").strip():
            r[col["sliceid"]] = _slice_id(_cell(r, col, "sliceid"), sample, names)
        for nm in ("analyst", "owner"):
            if _cell(r, col, nm).strip():
                r[col[nm]] = re.sub(r"[^,;/&+]+", lambda m: _person(m.group(0), names), _cell(r, col, nm))
        if _cell(r, col, "culturestart").strip():
            r[col["culturestart"]] = _shift_iso(_cell(r, col, "culturestart"), days)
        v = _cell(r, col, "comment")
        if v.strip():
            v = _PATH.sub("", v).replace(old_stem, new_stem)
            if pre is not None:
                v = _replace_initials(v, pre, suf, names, True)
            r[col["comment"]] = v = _shift_text_dates(v, days)
            comments.append(v)
    buf = io.StringIO()
    csv.writer(buf, lineterminator=nl).writerows(rows)
    out = buf.getvalue()
    if not txt.endswith(("\n", "\r")):
        out = out[:-len(nl)]
    return out, comments


def _json_strings(o):
    if isinstance(o, _Obj):
        return [s for k, v in o for s in [k] + _json_strings(v)]
    if isinstance(o, list):
        return [s for x in o for s in _json_strings(x)]
    return [o] if isinstance(o, str) and not isinstance(o, _Raw) else []


def _log_texts(path):
    """(line number, text) of a log file: the value of every line, the strings of structured lines decoded"""
    txt = read_text(path)[0]
    out = []
    for i, ln in enumerate(txt.split("\r\n" if "\r\n" in txt else "\n"), start=1):
        f = ln.split(";", 4)
        v = f[4] if len(f) == 5 else ln
        if v.lstrip().startswith("{"):
            try:
                v = "\n".join(_json_strings(_loads(v.strip())))
            except (ValueError, RecursionError):
                pass
        out.append((i, v))
    return out


def _found(value, kind, text):
    """value in text? serial numbers, pnp, version, file name: anywhere; names, initials, IDs: as a whole word.
    Case-sensitive for the file name and for values of less than 4 characters."""
    flags = 0 if kind == "file name" or len(value) < 4 else re.IGNORECASE
    pat = re.escape(value) if kind in _SUBSTRING else r"(?<![^\W_])%s(?![^\W_])" % re.escape(value)
    return re.search(pat, text, flags) is not None


def find_left(files, values, replacements=()):
    """the original values still in the output files. files: (file name, [(line number, text)]); values: original
    value -> kind; values found in a replacement text (pseudonyms, 'PC', new name, ...) are not searched.
    returns [(file name, line number, kind, value)]."""
    vals = [(v, k) for v, k in values.items() if v and not any(_found(v, k, r) for r in replacements)]
    return [(fn, i, k, v) for fn, lines in files for i, t in lines for v, k in vals if _found(v, k, t)]


def anonymize(mdd, new_name, outdir, date="2000-01-01", mat=None, show=False, initials=(), map_file=None):
    mdd = os.path.abspath(mdd)
    stem = os.path.splitext(os.path.basename(mdd))[0]
    log = os.path.join(os.path.dirname(mdd), stem + "_log.log")
    labels = os.path.join(os.path.dirname(mdd), stem + "_labels.csv")
    initials = [x for x in initials if x]
    out = {e: os.path.join(outdir, new_name + e) for e in (".mdd", "_log.log", "_labels.csv", ".mat")}
    if os.path.abspath(out[".mdd"]) == mdd:
        raise ValueError("the output would replace the recording: choose another new_name or --outdir")
    names = Pseudonyms(map_file)
    txt, enc, bom = read_text(log)
    d0 = first_date(txt.splitlines())
    days = (dt.date.fromisoformat(date) - d0).days if d0 else 0
    new_txt, comments = anonymize_log_text(txt, stem, new_name, days, initials, names)
    if os.path.isfile(labels):
        ltxt, lenc, lbom = _read_csv_text(labels)
        new_lbl, lcom = anonymize_labels_text(ltxt, stem, new_name, days, initials, names)
        comments += lcom
    os.makedirs(outdir, exist_ok=True)
    written = [out[".mdd"], out["_log.log"]]
    shutil.copyfile(mdd, out[".mdd"])
    # time of the last change of the copy: that of the recording, shifted by the same number of days in local time
    # (MyoDishAnalysis uses it to tell AM from PM in some logs with 12-hour time stamps)
    t = (dt.datetime.fromtimestamp(os.stat(mdd).st_mtime) + dt.timedelta(days=days)).timestamp()
    os.utime(out[".mdd"], (t, t))
    write_text(out["_log.log"], new_txt, enc, bom)
    files = [(new_name + "_log.log", _log_texts(out["_log.log"]))]
    whole = [(new_name + "_log.log", list(enumerate(read_text(out["_log.log"])[0].splitlines(), start=1)))]
    if os.path.isfile(labels):
        written.append(out["_labels.csv"])
        _write_csv_text(out["_labels.csv"], new_lbl, lenc, lbom)
        lines = _read_csv_text(out["_labels.csv"])[0].splitlines()
        files.append((new_name + "_labels.csv", list(enumerate(lines, start=1))))
        whole.append(files[-1])
    if mat:
        written.append(out[".mat"])
        com = _anonymize_mat(mat, out[".mat"], days)
        files.append((new_name + ".mat (comtext)", list(enumerate(com, start=1))))
        whole.append(files[-1])
    # final check: no original value that was replaced may be left (e.g. in a free-text comment)
    values = dict(names.originals)
    for x in initials:
        values.setdefault(x, "initials")
    if stem not in new_name:
        values.setdefault(stem, "file name")
    repl = [p for m in names.map.values() for p in m.values()] + list(_FIXED.values()) + [new_name]
    left = find_left(files, values, repl)
    # ... and no date of the recording (the dates of the log lines before the shift)
    dates = (_log_dates(txt.splitlines()) + sorted(names.dates)) if days else []
    rx = _dates_regex(set(dates) - {d + dt.timedelta(days=days) for d in dates})
    if rx is not None:
        left += [(fn, i, "date", m.group(0)) for fn, lines in whole for i, x in lines for m in [rx.search(x)] if m]
    if left:
        for p in written:
            if os.path.isfile(p):
                os.remove(p)
        rows = ["  %s line %d: %s '%s'" % x for x in left[:20]] + (["  ..."] if len(left) > 20 else [])
        raise AnonymizationError("original values are still in the output (output files deleted):\n" + "\n".join(rows)
                                 + "\nRemove them (initials in comments: --initials; dates in other forms or other"
                                 " values: edit a copy of the recording), then run again.")
    if map_file:
        names.save(map_file)
    if names.unreadable:
        print("   %d structured log line(s) could not be read and were kept unchanged (line %s)"
              % (len(names.unreadable), ", ".join(str(i) for i in names.unreadable)))
    if show:
        for c in sorted(set(comments)):
            print("   comment:", c)
        for c in sorted(set(names.texts)):
            print("   structured:", c)
        for v, k in names.originals.items():
            if k in names.map and v in names.map[k]:
                print("   %s: %s -> %s" % (k, v, names.map[k][v]))
    return days


def _anonymize_mat(src, dst, days):
    """writes the LabChart .mat with shifted times; returns the comment texts"""
    import numpy as np
    import scipy.io as sio
    S = sio.loadmat(src)
    S = {k: v for k, v in S.items() if not k.startswith("__")}
    if "blocktimes" in S:
        S["blocktimes"] = S["blocktimes"] + float(days)
    com = []
    if "comtext" in S and S["comtext"].size:
        com = [_shift_text_dates(str(r), days) for r in S["comtext"]]
        S["comtext"] = np.array(com)
    sio.savemat(dst, S, do_compression=True)
    return com


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("mdd")
    p.add_argument("new_name")
    p.add_argument("--outdir", default=".")
    p.add_argument("--date", default="2000-01-01", help="date of the first log entry after anonymization")
    p.add_argument("--mat", help="LabChart .mat export of a parallel EP recording")
    p.add_argument("--initials", default="", help="comma-separated initials to replace by pseudonyms, e.g. AB,CD")
    p.add_argument("--map", help="JSON file with the pseudonyms, read before and written after (the same pseudonyms "
                                 "for all recordings of a study); contains the original values: do not share it")
    p.add_argument("--show", action="store_true", help="print all comments and pseudonyms for review")
    a = p.parse_args(argv)
    try:
        days = anonymize(a.mdd, a.new_name, a.outdir, a.date, a.mat, a.show,
                         [x.strip() for x in a.initials.split(",")], a.map)
    except AnonymizationError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    print("%s -> %s (dates shifted by %d days)" % (os.path.basename(a.mdd), a.new_name, days))


if __name__ == "__main__":
    sys.exit(main())
