"""Anonymize a MyoDish recording (.mdd + _log.log, optionally the LabChart .mat of a parallel EP recording) for sharing.

    python anonymize_recording.py <recording.mdd> <new_name> [--outdir DIR] [--date 2000-01-01] [--mat FILE.mat]

What is changed (the .mdd data file is only copied under the new name):
  - systemTime of all log lines: shifted by a whole number of days so that the first entry falls on --date
    (time of day and all time differences are kept; dataLogTime, i.e. the time in the .mdd file, is unchanged).
  - dates in comments ('Started parallel recording: 01/Jan/2000 12:00:00'): same shift; software build date removed.
  - Windows paths (user names, folders with dates or sample IDs): reduced to the file name; the recording's own
    file names are replaced by <new_name>.mdd / <new_name>_log.log.
  - software version: build number removed ('Version 2.0.9708.42745' -> 'Version 2.0'; it encodes the build date).
  - initials given with --initials AB,CD: 'AB: comment' -> 'comment', '_AB' in protocol (schedule file) names removed.
  - connectedDevice (serial number of the USB adapter): replaced by a generic text.
  - LabChart .mat (--mat): blocktimes shifted by the same number of days; comtext dates shifted.
Line order, codes, channels and all numbers used by the analysis are kept, so MyoDishAnalysis gives the same
results (clock times shifted by the same number of days). Check the free-text comments yourself (--show) before
sharing: names or other identifying words inside comments cannot be recognized automatically.

TS 2026-10-07
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import shutil
import sys

_SYS = re.compile(r"^(\s*)(\d{4}) (\d{2}) (\d{2}) (\d{2}:\d{2}:\d{2}(?::\d+)?)(.*)$")
_PATH = re.compile(r"[A-Za-z]:\\(?:[^\\\r\n]*\\)*")  # directory part of a Windows path
_MONTHS = {"jan": 1, "feb": 2, "mar": 3, "mrz": 3, "mär": 3, "apr": 4, "may": 5, "mai": 5, "jun": 6, "jul": 7,
           "aug": 8, "sep": 9, "oct": 10, "okt": 10, "nov": 11, "dec": 12, "dez": 12}
_MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
_DATE_TXT = re.compile(r"(\d{1,2})([./])([A-Za-zä]{3})\2(\d{4})")      # 01/Mar/2000, 01.Mrz.2000
_DATE_NUM = re.compile(r"(\d{1,2})([./])(\d{1,2})\2(\d{4})")           # 31.01.2000, 18/03/2000


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


def first_date(lines):
    for ln in lines:
        m = _SYS.match(ln.split(";", 1)[0])
        if m:
            return dt.date(int(m.group(2)), int(m.group(3)), int(m.group(4)))
    return None


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


def anonymize_log_text(txt, old_stem, new_stem, days, initials=()):
    """returns the anonymized text and the list of comment texts (for review)."""
    ini = "|".join(re.escape(x) for x in initials if x)
    pre = re.compile(r"^\s*(?:%s)\s*:\s*" % ini) if ini else None
    suf = re.compile(r"_(?:%s)(?=[_.\s)]|$)" % ini) if ini else None
    nl = "\r\n" if "\r\n" in txt else "\n"
    lines = txt.split(nl)
    out, comments = [], []
    for ln in lines:
        f = ln.split(";", 4)
        if len(f) < 5:
            out.append(ln)
            continue
        m = _SYS.match(f[0])
        if m:
            d = dt.date(int(m.group(2)), int(m.group(3)), int(m.group(4))) + dt.timedelta(days=days)
            f[0] = "%s%04d %02d %02d %s%s" % (m.group(1), d.year, d.month, d.day, m.group(5), m.group(6))
        code, v = f[3].strip().lower(), f[4]
        v = _PATH.sub("", v)                         # paths -> file names
        v = v.replace(old_stem, new_stem)            # own file names
        if code == "programinfo" and v.strip().lower().startswith("version"):
            mv = re.match(r"(\s*[Vv]ersion\s+)(\d+)\.(\d+)", v)
            v = (mv.group(1) + mv.group(2) + "." + mv.group(3)) if mv else "Version"
        elif code == "programinfo" and v.strip().lower().startswith("date"):
            v = "Date"                               # build date (would allow to undo the date shift)
        elif code == "connecteddevice":
            v = "USB serial device"
        if pre is not None:
            if code == "comment":
                v = pre.sub("", v)
            v = suf.sub("", v)
        v = _shift_text_dates(v, days)
        f[4] = v
        if code == "comment":
            comments.append(v)
        out.append(";".join(f))
    return nl.join(out), comments


def anonymize(mdd, new_name, outdir, date="2000-01-01", mat=None, show=False, initials=()):
    mdd = os.path.abspath(mdd)
    stem = os.path.splitext(os.path.basename(mdd))[0]
    log = os.path.join(os.path.dirname(mdd), stem + "_log.log")
    txt, enc, bom = read_text(log)
    d0 = first_date(txt.splitlines())
    days = (dt.date.fromisoformat(date) - d0).days if d0 else 0
    new_txt, comments = anonymize_log_text(txt, stem, new_name, days, initials)
    os.makedirs(outdir, exist_ok=True)
    shutil.copyfile(mdd, os.path.join(outdir, new_name + ".mdd"))
    write_text(os.path.join(outdir, new_name + "_log.log"), new_txt, enc, bom)
    if mat:
        _anonymize_mat(mat, os.path.join(outdir, new_name + ".mat"), days)
    if show:
        for c in sorted(set(comments)):
            print("   comment:", c)
    return days


def _anonymize_mat(src, dst, days):
    import numpy as np
    import scipy.io as sio
    S = sio.loadmat(src)
    S = {k: v for k, v in S.items() if not k.startswith("__")}
    if "blocktimes" in S:
        S["blocktimes"] = S["blocktimes"] + float(days)
    if "comtext" in S and S["comtext"].size:
        S["comtext"] = np.array([_shift_text_dates(str(r), days) for r in S["comtext"]])
    sio.savemat(dst, S, do_compression=True)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("mdd")
    p.add_argument("new_name")
    p.add_argument("--outdir", default=".")
    p.add_argument("--date", default="2000-01-01", help="date of the first log entry after anonymization")
    p.add_argument("--mat", help="LabChart .mat export of a parallel EP recording")
    p.add_argument("--initials", default="", help="comma-separated initials to remove, e.g. AB,CD")
    p.add_argument("--show", action="store_true", help="print all comments for review")
    a = p.parse_args(argv)
    days = anonymize(a.mdd, a.new_name, a.outdir, a.date, a.mat, a.show, [x.strip() for x in a.initials.split(",")])
    print("%s -> %s (dates shifted by %d days)" % (os.path.basename(a.mdd), a.new_name, days))


if __name__ == "__main__":
    sys.exit(main())
