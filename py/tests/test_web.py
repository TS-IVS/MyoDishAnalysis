# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""MyoDishAnalysis in the browser (web/server.py, 2026-11-12): the interface of the local web server on a results
folder made by the watcher from an example recording."""
import importlib
import json
import os
import shutil
import threading
import time
import urllib.error
import urllib.request

import pytest

from myodish_analysis.web import make_server

W = importlib.import_module("myodish_analysis.watch")   # (the package exports the function watch)

EX = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "examples"))
NAME = "example9_ratVentricle"


@pytest.fixture(scope="module")
def site(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("web")
    raw, res = str(tmp / "raw"), str(tmp / "results")
    os.makedirs(os.path.join(raw, "E"))
    for ext in (".mdd", "_log.log", "_labels.csv"):
        if os.path.isfile(os.path.join(EX, NAME + ext)):
            shutil.copy(os.path.join(EX, NAME + ext), os.path.join(raw, "E", NAME + ext))
    W.watch(raw, res, quiet=True, min_file_age_minutes=0)
    srv, app = make_server(res, raw, port=0)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    yield "http://127.0.0.1:%d" % srv.server_address[1], raw, res, app
    srv.shutdown()
    srv.server_close()


def _get(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.status, r.headers.get("Content-Type", ""), r.read()


def _json(url, data=None, headers=None):
    req = urllib.request.Request(url, headers=dict(headers or {}))
    if data is not None:
        req.data = json.dumps(data).encode("utf-8")
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8"))


def test_page_state_and_results(site):
    url, raw, res, _ = site
    code, ctype, body = _get(url + "/")
    assert code == 200 and ctype.startswith("text/html") and b"MyoDishAnalysis" in body and b"/api/results" in body
    code, st = _json(url + "/api/state")
    assert code == 200 and st["results"] == os.path.abspath(res) and st["raw"] == os.path.abspath(raw)
    assert st["hasIndex"]
    assert len(st["names"]) == 13 and len(st["legend"]) == 3 and st["minBeats"] == 50
    code, R = _json(url + "/api/results")
    rows = R["rows"]
    assert code == 200 and R["recordings"] == 1 and R["missing"] == [] and len(rows) >= 1
    r = rows[0]
    assert r["file"] == "E/" + NAME + ".mdd" and r["channel"] == 1 and r["indexStatus"] == "ok"
    assert set(r) >= {"label", "status", "nDetected", "capture", "flags", "words", "level", "red", "sensor", "yellow",
                      "peakSignal", "offset", "window", "image", "report", "workbook", "open", "note"}
    assert r["report"].endswith("E_report.pdf") and r["workbook"].endswith(NAME + ".xlsx") and os.path.isfile(r["open"])
    # the files of the page: served from the results folder, nothing else
    code, ctype, body = _get(url + r["report"])
    assert code == 200 and ctype == "application/pdf" and body[:4] == b"%PDF"
    if r["image"]:
        code, ctype, body = _get(url + r["image"])
        assert code == 200 and ctype == "image/png"
    for bad in ("/files/../" + os.path.basename(raw) + "/E/" + NAME + ".mdd", "/files/%2e%2e/%2e%2e/etc/hosts",
                "/files/mda_watch.lock", "/files/nothing.png"):
        code, j = _json(url + bad)
        assert code in (400, 404) and "error" in j, bad


def test_flags_are_computed_again(site):
    url, _, res, _ = site
    os.remove(os.path.join(res, W.FLAGS_NAME))
    code, R = _json(url + "/api/results")
    assert code == 200 and R["missing"] == ["E/" + NAME + ".mdd"] and R["rows"][0]["channel"] is None
    assert R["rows"][0]["note"] == "flags not computed yet"
    code, j = _json(url + "/api/flags/compute", {})
    assert code == 200 and j["missing"] == [] and j["rows"] >= 1
    code, R = _json(url + "/api/results")
    assert R["missing"] == [] and R["rows"][0]["channel"] == 1 and os.path.isfile(os.path.join(res, W.FLAGS_NAME))


def test_watcher_state_reports_and_a_pass(site):
    url, raw, res, app = site
    code, w = _json(url + "/api/watcher")
    assert code == 200 and w["recordings"] == 1 and w["counts"] == {"ok": 1} and w["raw"] == os.path.abspath(raw)
    assert len(w["reports"]) == 1 and not w["run"]["running"] and not w["locked"] and w["lastAnalyzed"]
    code, j = _json(url + "/api/report?name=" + w["reports"][0])
    assert code == 200 and "watcher report" in j["text"] and "raw folder:" in j["text"]
    for bad in ("../mda_index.csv", "mda_index.csv", ""):
        code, j = _json(url + "/api/report?name=" + bad)
        assert code == 400 and "error" in j
    # a request from a page of another site is refused; a pass on a folder that does not exist too
    code, j = _json(url + "/api/watcher/run", {"dry_run": True}, {"Origin": "http://example.org"})
    assert code == 403
    code, j = _json(url + "/api/watcher/run", {"raw": os.path.join(raw, "no such folder")})
    assert code == 400 and "raw folder not found" in j["error"]
    # one pass (list only): nothing new, the state says so
    code, j = _json(url + "/api/watcher/run", {"dry_run": True})
    assert code == 200 and j["started"]
    for _ in range(600):
        code, w = _json(url + "/api/watcher")
        if not w["run"]["running"]:
            break
        time.sleep(0.1)
    assert not w["run"]["running"] and w["run"]["finished"] and w["run"]["error"] == "" and w["run"]["dry_run"]
    assert "0 recording(s) to analyse" in w["run"]["output"]   # what the pass printed is shown on the page
    assert app.raw_of_last_report() == os.path.abspath(raw)
    # a pass that analyzes from another raw folder than the one of the last pass is refused until confirmed
    other = os.path.join(raw, "E")   # one level too deep: every recording would count as new
    code, j = _json(url + "/api/watcher/run", {"raw": other})
    assert code == 400 and j["code"] == "otherRaw" and "another raw folder" in j["error"]
    code, j = _json(url + "/api/watcher/run", {"raw": other, "dry_run": True})   # the list is always allowed
    assert code == 200 and j["started"]
    for _ in range(600):
        code, w = _json(url + "/api/watcher")
        if not w["run"]["running"]:
            break
        time.sleep(0.1)
    assert not w["run"]["running"] and os.path.join("raw", "E") + ": " in w["run"]["output"]
    assert w["lastRaw"] == os.path.abspath(raw)   # a list writes no report: the folder of the last pass stays
    code, j = _json(url + "/api/nothing")
    assert code == 404
