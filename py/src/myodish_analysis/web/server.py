# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""MyoDishAnalysis in the browser (2026-11-12, first step): the results of a results folder of the watcher and the
state of the watcher, served by a small local web server. Standard library only.

    mda-web RESULTS [--raw RAW] [--port 8765] [--host 127.0.0.1] [--no-browser]
    serve(results_folder, raw_folder=None, host="127.0.0.1", port=8765, open_browser=True)

The server runs on the computer that holds the data and answers on 127.0.0.1 only, unless another host is given: with
--host 0.0.0.0 every computer that reaches this one can read the results and start a pass, and there is no login. Use
that inside a trusted network only.

Pages (one file, static/index.html): the start page, the results browser (one row per recording and channel with its
flags in words, filters, search; a row shows the texts of the flags, the trend image of the channel, the report of the
experiment and the command that opens the place in the desktop GUI) and the watcher (what is analysed, the reports of
the last passes, one pass now).

Interface (JSON unless noted):
    GET  /api/state                 results and raw folder, version, names of the flags, legend
    GET  /api/results               rows of the results browser, files without current flags
    POST /api/flags/compute         computes the missing flags from the result files (flags_table(compute=True))
    GET  /api/watcher               counts of the index by status, reports of the passes, state of a pass started here
    GET  /api/report?name=...       text of one pass report (results/reports/<name>)
    POST /api/watcher/run           {"raw": folder, "dry_run": bool, "other_raw": bool}: one pass in the background
                                    (watch) with the standard options of the analysis; what it prints is in
                                    run.output of the state. A pass from another raw folder than the one of the last
                                    pass is refused (code "otherRaw") unless other_raw is true or it only lists
    GET  /files/<path>              a file of the results folder (images, PDF reports, tables), nothing outside it
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as _dt
import io
import json
import math
import mimetypes
import os
import re
import sys
import threading
import traceback
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_STATIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
_REPORT_RX = re.compile(r"^mda_report_[0-9_\-]+\.txt$")
_SERVED = {".png", ".jpg", ".pdf", ".txt", ".csv", ".gz", ".xlsx", ".json"}


class App:
    """state of one server: the folders and the pass started from the page (at most one at a time)"""

    def __init__(self, results_folder, raw_folder=None):
        self.results = os.path.abspath(results_folder)
        self.raw = os.path.abspath(raw_folder) if raw_folder else ""
        self.lock = threading.Lock()
        self.run = dict(running=False, started="", finished="", raw="", dry_run=False, report="", error="")

    # ------------------------------------------------------------------------------------------- data
    def state(self):
        from .. import report
        from ..write_results import mda_version
        return dict(results=self.results, raw=self.raw or self.raw_of_last_report(), version=mda_version(),
                    hasIndex=os.path.isfile(os.path.join(self.results, "mda_index.csv")),
                    names=[dict(letter=c, group=g, name=n) for c, g, n in report.FLAG_NAMES],
                    legend=report.short_legend(), minBeats=report.FLAG_DEFAULTS["min_beats"])

    def results_rows(self):
        """one row per analysed recording and channel (flags of the current analyses), one per recording without"""
        from .. import report
        from ..watch import flags_table, results_of
        X, T, missing = flags_table(self.results, compute=False)
        msg = dict(zip(X["file"], X["message"].fillna("").astype(str)))
        st = dict(zip(X["file"], X["status"].astype(str)))
        ana = dict(zip(X["file"], X["analyzed"].astype(str)))
        rows, have, folders = [], set(), {}
        for r in T.to_dict("records"):
            f = str(r["file"])
            have.add(f)
            if f not in folders:
                folders[f] = self._links(f, results_of(self.results, f)[0])
            ch = int(r["channel"])
            L = folders[f]
            img = L["images"].get(ch, "")
            rows.append(dict(file=f, channel=ch, label=_s(r["label"]), status=_s(r["status"]),
                             nDetected=_n(r["nDetected"]), capture=_n(r["capture_percent"]), flags=_s(r["flags"]),
                             words=report.flag_words(_s(r["flags"])), level=_s(r["level"]), red=_s(r["red"]),
                             sensor=_s(r.get("sensor", "")), yellow=_s(r["yellow"]), peakSignal=_n(r["peakSignal_AU"]),
                             offset=_n(r["offset_AU"]), window=[_n(r["from"]), _n(r["to"])], indexStatus="ok",
                             analyzed=ana.get(f, ""), image=img, report=L["report"], workbook=L["workbook"],
                             open=L["open"], experiment=L["experiment"], note=""))
        for f in X["file"]:
            if f in have:
                continue
            ok = st.get(f) == "ok"
            rows.append(dict(file=f, channel=None, label="", status="", nDetected=None, capture=None, flags="",
                             words="", level="", red="", sensor="", yellow="", peakSignal=None, offset=None,
                             window=[None, None], indexStatus=st.get(f, ""), analyzed=ana.get(f, ""), image="",
                             report="", workbook="", open="", experiment=f.replace("\\", "/").rpartition("/")[0],
                             note="flags not computed yet" if ok else msg.get(f, "")))
        rows.sort(key=lambda r: (r["file"], r["channel"] or 0))
        return dict(rows=rows, missing=list(missing), recordings=int(len(X)))

    def _links(self, rel, folder):
        """urls of the files that belong to a recording: trend image per channel, workbook, report of the experiment"""
        rel = rel.replace("\\", "/")
        name = re.sub(r"\.mdd$", "", rel.rsplit("/", 1)[-1], flags=re.I)
        exp = rel.rpartition("/")[0]
        images = {}
        for d in (folder, os.path.join(folder, "trends")):
            if not os.path.isdir(d):
                continue
            for fn in os.listdir(d):
                m = re.fullmatch(re.escape(name) + r"_ch(\d+)\.png", fn)
                if m and int(m.group(1)) not in images:
                    images[int(m.group(1))] = self._url(os.path.join(d, fn))
        wb = os.path.join(folder, name + ".xlsx")
        rep = os.path.join(self.results, *exp.split("/"), exp.rsplit("/", 1)[-1] + "_report.pdf") if exp else \
            os.path.join(self.results, "mda_report_root.pdf")
        info = os.path.join(folder, name + "_info.csv")
        return dict(images=images, workbook=self._url(wb) if os.path.isfile(wb) else "",
                    open=wb if os.path.isfile(wb) else info if os.path.isfile(info) else "",
                    report=self._url(rep) if os.path.isfile(rep) else "", experiment=exp)

    def _url(self, path):
        rel = os.path.relpath(path, self.results).replace(os.sep, "/")
        return "/files/" + urllib.parse.quote(rel)

    def compute_flags(self):
        from ..watch import flags_table
        _, T, missing = flags_table(self.results, compute=True)
        return dict(rows=int(len(T)), missing=list(missing))

    def watcher(self):
        from ..watch import LOCK_HOURS, LOCK_NAME, read_index
        X = read_index(self.results)
        counts = {str(k): int(v) for k, v in X["status"].value_counts().items()}
        last = max((a for a in X["analyzed"].astype(str) if a), default="")
        lock = os.path.join(self.results, LOCK_NAME)
        busy = os.path.isfile(lock) and (_dt.datetime.now().timestamp() - os.path.getmtime(lock)) < LOCK_HOURS * 3600
        d = os.path.join(self.results, "reports")
        reports = sorted((f for f in os.listdir(d) if _REPORT_RX.match(f)), reverse=True)[:30] \
            if os.path.isdir(d) else []
        with self.lock:
            run = dict(self.run)
        return dict(recordings=int(len(X)), counts=counts, lastAnalyzed=last, locked=bool(busy), reports=reports,
                    raw=self.raw or self.raw_of_last_report(), lastRaw=self.raw_of_last_report(), run=run)

    def raw_of_last_report(self):
        """raw folder named in the newest pass report ('' if there is none)"""
        d = os.path.join(self.results, "reports")
        if not os.path.isdir(d):
            return ""
        for f in sorted((f for f in os.listdir(d) if _REPORT_RX.match(f)), reverse=True)[:1]:
            try:
                with open(os.path.join(d, f), encoding="utf-8", errors="replace") as fh:
                    for line in fh.read(4000).splitlines():
                        if line.startswith("raw folder:"):
                            return line.split(":", 1)[1].strip()
            except OSError:
                pass
        return ""

    def report_text(self, name):
        if not _REPORT_RX.match(name or ""):
            raise ValueError("not a pass report")
        with open(os.path.join(self.results, "reports", name), encoding="utf-8", errors="replace") as fh:
            return fh.read()

    def start_pass(self, raw, dry_run=False, other_raw=False):
        """one pass of the watcher in the background; refused while one runs (here or elsewhere: lock file). A pass
        that analyzes is also refused (OtherRaw) when the results folder was filled from another raw folder, unless
        other_raw is set: the recordings are known by their path below the raw folder, so from a folder one level
        up or down every recording counts as new and is analyzed a second time."""
        last = self.raw_of_last_report()
        raw = os.path.abspath(raw or self.raw or last or "")
        if not raw or not os.path.isdir(raw):
            raise ValueError("raw folder not found: " + (raw or "(none given)"))
        if last and not dry_run and not other_raw and not _same_folder(last, raw):
            raise OtherRaw(f"This results folder was filled from another raw folder ({last}). From {raw} the "
                           "recordings may count as new and be analyzed a second time. Look at the list first "
                           "('Show what would be analyzed').")
        with self.lock:
            if self.run["running"]:
                raise ValueError("a pass started here is still running")
            self.run = dict(running=True, started=_now(), finished="", raw=raw, dry_run=bool(dry_run), report="",
                            error="", output="")
        threading.Thread(target=self._pass, args=(raw, bool(dry_run)), daemon=True).start()
        return dict(started=True)

    def _pass(self, raw, dry_run):
        report, error = "", ""
        try:
            from ..watch import watch
            with contextlib.redirect_stdout(_Tee(self, sys.stdout)):  # the lines of the pass, for the page
                _, report = watch(raw, self.results, quiet=False, dry_run=dry_run)
        except Exception as e:  # noqa: BLE001 - shown on the page
            error = f"{type(e).__name__}: {e}"
            if os.environ.get("MDA_DEBUG"):
                traceback.print_exc()
        with self.lock:
            self.run.update(running=False, finished=_now(), report=str(report or ""), error=error)

    def file_path(self, rel):
        """absolute path of a file of the results folder; ValueError for anything outside it or of another kind"""
        p = os.path.realpath(os.path.join(self.results, *[s for s in rel.split("/") if s]))
        root = os.path.realpath(self.results)
        if os.path.commonpath([p, root]) != root or not os.path.isfile(p):
            raise ValueError("not a file of the results folder")
        if os.path.splitext(p)[1].lower() not in _SERVED:
            raise ValueError("this kind of file is not served")
        return p


class OtherRaw(ValueError):
    """a pass from another raw folder than the one of the last pass (the page asks before it goes on)"""


def _same_folder(a, b):
    def norm(p):
        return os.path.normcase(os.path.realpath(os.path.abspath(p))).rstrip("\\/")
    return norm(a) == norm(b)


class _Tee(io.TextIOBase):
    """what a pass prints goes to the terminal as before and, for the page, into the state of the pass (the last
    20000 characters)"""

    def __init__(self, app, out):
        self.app, self.out = app, out

    def write(self, s):
        with self.app.lock:
            self.app.run["output"] = (self.app.run.get("output", "") + s)[-20000:]
        try:
            self.out.write(s)
        except (OSError, ValueError):
            pass
        return len(s)

    def flush(self):
        try:
            self.out.flush()
        except (OSError, ValueError):
            pass


def _now():
    return _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _s(v):
    return "" if v is None or (isinstance(v, float) and math.isnan(v)) else str(v)


def _n(v):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(v) or math.isinf(v) else v


def make_handler(app):
    class Handler(BaseHTTPRequestHandler):
        server_version = "MyoDishAnalysisWeb"

        def log_message(self, *a):  # quiet: no request log in the terminal
            return

        def _json(self, obj, code=200):
            body = json.dumps(obj, allow_nan=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _file(self, path, ctype=None):
            ctype = ctype or mimetypes.guess_type(path)[0] or "application/octet-stream"
            with open(path, "rb") as fh:
                body = fh.read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _do(self, fn):
            try:
                fn()
            except OtherRaw as e:
                self._json(dict(error=str(e), code="otherRaw"), 400)
            except ValueError as e:
                self._json(dict(error=str(e)), 400)
            except FileNotFoundError:
                self._json(dict(error="not found"), 404)
            except Exception as e:  # noqa: BLE001 - the page shows the message
                if os.environ.get("MDA_DEBUG"):
                    traceback.print_exc()
                self._json(dict(error=f"{type(e).__name__}: {e}"), 500)

        def do_GET(self):  # noqa: N802
            u = urllib.parse.urlsplit(self.path)
            q = urllib.parse.parse_qs(u.query)
            path = urllib.parse.unquote(u.path)
            if path in ("/", "/index.html"):
                return self._do(lambda: self._file(os.path.join(_STATIC, "index.html"), "text/html; charset=utf-8"))
            if path == "/api/state":
                return self._do(lambda: self._json(app.state()))
            if path == "/api/results":
                return self._do(lambda: self._json(app.results_rows()))
            if path == "/api/watcher":
                return self._do(lambda: self._json(app.watcher()))
            if path == "/api/report":
                return self._do(lambda: self._json(dict(text=app.report_text((q.get("name") or [""])[0]))))
            if path.startswith("/files/"):
                return self._do(lambda: self._file(app.file_path(path[len("/files/"):])))
            self._json(dict(error="not found"), 404)

        def do_POST(self):  # noqa: N802
            n = int(self.headers.get("Content-Length") or 0)
            try:
                data = json.loads(self.rfile.read(n).decode("utf-8") or "{}") if n else {}
            except ValueError:
                return self._json(dict(error="not JSON"), 400)
            # a page of another site must not start a pass in the name of the user: same-origin requests only
            origin = self.headers.get("Origin")
            if origin and urllib.parse.urlsplit(origin).netloc != self.headers.get("Host"):
                return self._json(dict(error="request from another site refused"), 403)
            path = urllib.parse.urlsplit(self.path).path
            if path == "/api/flags/compute":
                return self._do(lambda: self._json(app.compute_flags()))
            if path == "/api/watcher/run":
                return self._do(lambda: self._json(app.start_pass(data.get("raw"), bool(data.get("dry_run", False)),
                                                                bool(data.get("other_raw", False)))))
            self._json(dict(error="not found"), 404)

    return Handler


def make_server(results_folder, raw_folder=None, host="127.0.0.1", port=8765):
    """(server, app): the server is not started yet (serve_forever), port 0 = any free port"""
    app = App(results_folder, raw_folder)
    return ThreadingHTTPServer((host, int(port)), make_handler(app)), app


def serve(results_folder, raw_folder=None, host="127.0.0.1", port=8765, open_browser=True):
    srv, _ = make_server(results_folder, raw_folder, host, port)
    url = "http://%s:%d/" % ("127.0.0.1" if host in ("0.0.0.0", "") else host, srv.server_address[1])
    print(f"MyoDishAnalysis in the browser: {url}   (results: {os.path.abspath(results_folder)}; stop with Ctrl+C)")
    if host not in ("127.0.0.1", "localhost"):
        print("Note: other computers can reach this page. There is no login: use it in a trusted network only.")
    if open_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


def main(argv=None):
    ap = argparse.ArgumentParser(prog="mda-web", description="MyoDishAnalysis in the browser: results browser and "
                                 "watcher of a results folder (local web server, this computer only by default)")
    ap.add_argument("results", help="results folder of the watcher (with mda_index.csv)")
    ap.add_argument("--raw", help="raw folder with the recordings (for a pass started from the page; default: the "
                    "one named in the newest pass report)")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1", help="127.0.0.1 (default): this computer only; 0.0.0.0: every "
                    "computer that reaches this one (no login, trusted networks only)")
    ap.add_argument("--no-browser", action="store_true", help="do not open the page in the browser")
    a = ap.parse_args(argv)
    serve(a.results, a.raw, a.host, a.port, not a.no_browser)
