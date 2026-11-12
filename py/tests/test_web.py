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
import urllib.parse
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


def test_settings_page_save_and_use(site):
    url, raw, res, app = site
    from myodish_analysis.options import options
    from myodish_analysis.settings import load_settings
    file = os.path.join(res, "mda_web_settings.csv")
    code, s = _json(url + "/api/settings")
    assert code == 200 and s["source"] == "standard" and not s["saved"] and s["changed"] == [] and s["file"] == file
    names = [f["name"] for f in s["fields"]]
    D, tabs = options(), {t["name"] for t in s["tabs"]}
    assert len(names) == len(set(names)) and all(n in D for n in names) and all(f["tab"] in tabs for f in s["fields"])
    assert all(n in names for b in s["basics"] for n in b["names"])   # every basic setting is a field of the page
    assert s["last"]["canLoad"] and s["last"]["differs"] == []       # the analysis of the fixture: standard settings
    # sent back unchanged: nothing differs from the defaults (no rounding by the way through the page)
    code, s2 = _json(url + "/api/settings", {"values": {f["name"]: f["value"] for f in s["fields"]}})
    assert code == 200 and s2["saved"] and s2["changed"] == [] and os.path.isfile(file) and s2["download"]
    # changed values: shown in the units of the page, saved in the units of the options
    new = {"rockerFilter": True, "gateMax": 120, "arrhythmicChannels": "1, 3", "detection": "specific"}
    code, s3 = _json(url + "/api/settings", {"values": new})
    assert code == 200 and sorted(s3["changed"]) == sorted(new)
    shown = {f["name"]: f["value"] for f in s3["fields"]}
    assert shown["gateMax"] == 120 and shown["arrhythmicChannels"] == "1 3" and shown["rockerFilter"] is True
    O = load_settings(file)
    assert abs(float(O["gateMax"]) - 0.12) < 1e-12 and bool(O["rockerFilter"]) and str(O["detection"]) == "specific"
    d = {x["name"]: x for x in s3["last"]["differs"]}   # the newest analysis was made with the standard settings
    assert sorted(d) == sorted(new) and d["gateMax"] == dict(name="gateMax", last="150 ms (standard)", page="120 ms")
    assert d["rockerFilter"]["page"] == "on" and d["detection"]["last"].endswith("(standard)")
    # a pass started from the page uses the file; the watcher page names what is changed
    assert app.pass_keywords() == {"settings": file}
    code, w = _json(url + "/api/watcher")
    assert sorted(w["settingsChanged"]) == sorted(new)
    code, j = _json(url + "/api/watcher/run", {"dry_run": True})
    assert code == 200
    for _ in range(600):
        code, w = _json(url + "/api/watcher")
        if not w["run"]["running"]:
            break
        time.sleep(0.1)
    assert w["run"]["error"] == "" and "recording(s) to analyse" in w["run"]["output"]
    text = W.options_text(W._expand_settings(app.pass_keywords()))   # the options such a pass records in the index
    assert "gatemax=0.12" in text and "rockerfilter=1" in text and "detection=specific" in text
    # what is not a value is refused with the name of the setting, and nothing is saved
    before = open(file, encoding="utf-8").read()
    for bad, word in (({"gateMax": "abc"}, "a number is expected"), ({"detection": "x"}, "one of these"),
                      ({"nope": 1}, "unknown setting"), ({"steadyStateBeats": 2.5}, "whole number"),
                      ({"rockerFilter": "yes"}, "on or off")):
        code, j = _json(url + "/api/settings", {"values": bad})
        assert code == 400 and word in j["error"], bad
    assert open(file, encoding="utf-8").read() == before
    # the settings of the newest analysis and of a settings file fill the page; saved is only what is sent to save
    code, s4 = _json(url + "/api/settings/last", {})
    assert code == 200 and s4["changed"] == [] and s4["source"].startswith("the newest analysis")
    code, s5 = _json(url + "/api/settings/file", {"text": before, "name": "mine.csv"})
    assert code == 200 and sorted(s5["changed"]) == sorted(new) and s5["source"] == "the file mine.csv"
    code, j = _json(url + "/api/settings/file", {"text": "hello", "name": "x.csv"})
    assert code == 400 and "not a settings file" in j["error"]
    assert open(file, encoding="utf-8").read() == before
    # back to the standard
    code, s6 = _json(url + "/api/settings", {"values": {f["name"]: f["default"] for f in s["fields"]},
                                             "base": "standard"})
    assert code == 200 and s6["changed"] == [] and s6["last"]["differs"] == []


def test_help_guides_and_page(site):
    url, raw, res, app = site
    code, h = _json(url + "/api/help")
    assert code == 200 and len(h["names"]) == 13 and h["localOnly"] and h["minBeats"] == 50
    assert any("150 ms" in x["text"] for x in h["legend"])   # the rules with the thresholds in use
    assert len(h["docs"]) == 3                               # source checkout: the guides are at hand
    for d in h["docs"]:
        code, ctype, body = _get(url + d["url"])
        assert code == 200 and ctype == "application/pdf" and body[:4] == b"%PDF"
    code, j = _json(url + "/docs/..%2FREADME.md")
    assert code == 404
    code, ctype, body = _get(url + "/")
    page = body.decode("utf-8")
    for word in ('id="settings"', 'id="help"', "What the colored notes mean", "First steps"):
        assert word in page
    assert "<script src" not in page and "<link" not in page and 'src="http' not in page   # nothing is loaded


def test_only_requests_to_this_computer(site):
    # a page of another site that points its own name at 127.0.0.1 reaches the server, but under its name: refused
    url, raw, res, app = site
    for path, data in (("/api/state", None), ("/api/results", None), ("/", None), ("/api/settings", {"values": {}})):
        code, j = _json(url + path, data, {"Host": "example.org:8765"})
        assert code == 403 and "this computer only" in j["error"], path
    code, j = _json(url + "/api/state", None, {"Host": "localhost:8765"})
    assert code == 200
    app.local_only = False   # started with --host 0.0.0.0: every name is answered
    try:
        code, j = _json(url + "/api/state", None, {"Host": "labpc.example:8765"})
        assert code == 200
    finally:
        app.local_only = True


def test_studies_design_run_and_view(tmp_path):
    """a study from the page: the design table is checked, the study runs in the background into
    <results>/studies/<name>, and its design, images, methods text and tables come back (synthetic results of
    test_timepoints)"""
    import base64
    from test_timepoints import _results
    res = _results(tmp_path)
    srv, app = make_server(res, port=0)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = "http://127.0.0.1:%d" % srv.server_address[1]
    try:
        code, st = _json(url + "/api/studies")
        assert code == 200 and st["studies"] == [] and not st["job"]["running"]
        assert [(x["series"], x["experiment"], x["recordings"]) for x in st["series"]] == [("rigT_S", "expT", 2)]
        assert st["columns"][:4] == ["series", "channel", "treatment", "time"]
        keys = [x["key"] for x in st["settings"]]   # the folders and the name are set by the page
        assert "offsets" in keys and "t0" in keys and not {"resultsFolder", "outputFolder", "name"} & set(keys)
        rows = [dict(series="rigT_S", channel=1, treatment="OME0.5uM", time="2000-01-01 12:00", sampleID="H1"),
                dict(series="rigT_S", channel="2", treatment="OME0.5uM", time="2000-01-01 12:00", sampleID="H1",
                     exclude="10", excludeReason="test reason"),
                dict(series="rigT_S", channel=3, treatment="CTRL", time="2000-01-01 12:00", sampleID="H2"),
                dict(series="")]   # an empty row of the editor
        ok = {"offsets": "-60, 10", "averageBeats": False, "figures": False}
        # mistakes are named before anything runs
        for name, settings, rws, word in (
                ("s1", {}, rows, "Windows"), ("a/b", ok, rows, "name of the study"), ("..", ok, rows, "name of the"),
                ("s1", ok, [], "table of slices is empty"), ("s1", ok, [dict(rows[0], series="nope")], "series nope"),
                ("s1", ok, [dict(rows[0], time="tomorrow")], "not a date and time"),
                ("s1", ok, [dict(rows[0], channel="x")], "not a number"),
                ("s1", ok, [dict(rows[0], treatment="two words")], "letters, digits"),
                ("s1", ok, [dict(rows[0], exclude="later")], "leave out"),
                ("s1", dict(ok, resultsFolder="/x"), rows, "unknown setting"),
                ("s1", dict(ok, offsets="soon"), rows, "numbers (minutes)")):
            code, j = _json(url + "/api/study/run", {"name": name, "settings": settings, "rows": rws})
            assert code == 400 and word in j["error"], (name, word, j)
        assert not os.path.isdir(os.path.join(res, "studies"))
        code, j = _json(url + "/api/study/run", {"name": "s1", "settings": ok, "rows": rows})
        assert code == 200 and j["started"]
        code, j = _json(url + "/api/study/run", {"name": "s2", "settings": ok, "rows": rows})   # one at a time
        code2, w = _json(url + "/api/watcher/run", {"dry_run": True, "raw": str(tmp_path)})
        for _ in range(1200):
            c, job = _json(url + "/api/job")
            if not job["running"]:
                break
            time.sleep(0.1)
        if job["name"] == "s1":   # the second study and the pass arrived while the first one ran: refused
            assert code == 400 and "still running" in j["error"] and code2 == 400 and "still running" in w["error"]
        assert job["finished"] and job["error"] == "" and job["kind"] == "study"
        d = os.path.join(res, "studies", "s1")
        assert sorted(os.listdir(d)) == ["analyses", "design_s1.xlsx", "s1.xlsx", "s1_methods.txt", "s1_prism.xlsx"]
        code, st = _json(url + "/api/studies")
        assert [(x["name"], x["done"], x["slices"], x["treatments"]) for x in st["studies"]] == [
            ("s1", True, 3, ["OME0.5uM", "CTRL"])]
        code, v = _json(url + "/api/study?name=s1")
        assert code == 200 and v["done"] and len(v["rows"]) == 3 and v["rows"][1]["exclude"] == "10"
        assert v["settings"]["offsets"] == "-60 10" and v["settings"]["averageBeats"] == "false"
        assert v["methods"].startswith("Contraction parameters were analysed with MyoDishAnalysis ")
        assert "Excluded: H1 rigT_S_ch2 (windows from +10 min; test reason)." in v["methods"]
        assert [t["sheet"] for t in v["tables"]] == ["treatments", "statistics", "excluded"]
        assert v["tables"][2]["rows"][0][v["tables"][2]["columns"].index("excludeReason")] == "test reason"
        titles = [f["title"] for f in v["files"]]
        assert titles[0].startswith("Workbook") and any(t.startswith("Design table") for t in titles)
        for f in v["files"]:
            code, ctype, body = _get(url + f["url"])
            assert code == 200 and len(body) > 100
        assert v["groups"] == []   # run without images
        for bad in ("nope", "..", "a/b", ""):
            code, j = _json(url + "/api/study?name=" + urllib.parse.quote(bad, safe=""))
            assert code in (400, 404), bad
        # the empty design table, and a design table loaded into the editor (nothing is saved or run)
        code, ctype, tpl = _get(url + "/api/study/template")
        assert code == 200 and tpl[:2] == b"PK"
        code, j = _json(url + "/api/study/design", {"data": base64.b64encode(tpl).decode(), "name": "design.xlsx"})
        assert code == 200 and len(j["rows"]) == 2 and j["rows"][1]["treatment"] == "PMA50nM"
        assert j["settings"]["offsets"] == "-30 10 60 180 360 720 1380"
        csv = "series,channel,treatment,time\nrigT_S,1,CTRL,2000-01-01 12:00\n".encode()
        code, j = _json(url + "/api/study/design", {"data": base64.b64encode(csv).decode(), "name": "d.csv"})
        assert code == 200 and j["rows"] == [dict(series="rigT_S", channel=1, treatment="CTRL",
                                                  time="2000-01-01 12:00", sampleID="", group="", exclude="",
                                                  excludeReason="")]
        for data, name, word in ((base64.b64encode(b"hello").decode(), "d.xlsx", "cannot be read"),
                                 (base64.b64encode(b"a,b\n1,2\n").decode(), "d.csv", "columns missing"),
                                 ("x", "d.pdf", ".xlsx or a .csv"), ("***", "d.csv", "did not arrive")):
            code, j = _json(url + "/api/study/design", {"data": data, "name": name})
            assert code == 400 and word in j["error"], (name, j)
        code, s0 = _json(url + "/api/state")
        assert s0["studies"] == 1
    finally:
        srv.shutdown()
        srv.server_close()


def _wait_pass(url):
    for _ in range(3000):
        code, w = _json(url + "/api/watcher")
        if not w["run"]["running"]:
            return w
        time.sleep(0.1)
    raise AssertionError("the pass did not end")


def test_pass_options_and_analyzing_again(site):
    """which recordings a pass takes (options of the watcher from the page), and a pass that analyzes again: asked
    first, then one real pass through the page"""
    url, raw, res, app = site
    run = url + "/api/watcher/run"
    for opts, word in (({"reanalyze": "some"}, "new, outdated or all"), ({"max_files": "0"}, "whole number"),
                       ({"workers": "many"}, "a number is expected"), ({"workers": 99}, "at most 16"),
                       ({"from_date": "soon"}, "a date is expected"), ({"retry_errors": "yes"}, "on or off"),
                       ({"min_file_age_minutes": -1}, "minutes from 0"), ({"nope": 1}, "unknown option")):
        code, j = _json(run, {"dry_run": True, "options": opts})
        assert code == 400 and word in j["error"], opts
    again = {"reanalyze": "all", "min_file_age_minutes": "0", "include": "", "max_files": "", "retry_errors": False}
    code, j = _json(run, {"dry_run": True, "options": again})   # empty fields of the page: defaults of the watcher
    assert code == 200
    w = _wait_pass(url)
    assert w["run"]["error"] == "" and "1 recording(s) to analyse" in w["run"]["output"]
    assert "(reanalyze all)" in w["run"]["output"] and w["run"]["options"] == {"reanalyze": "all",
                                                                              "min_file_age_minutes": 0.0}
    code, j = _json(run, {"dry_run": True, "options": dict(again, include="nothing*")})
    assert code == 200 and "0 recording(s) to analyse" in _wait_pass(url)["run"]["output"]
    code, j = _json(run, {"dry_run": True, "options": dict(again, from_date="2999-01-01")})
    assert code == 200 and "0 recording(s) to analyse" in _wait_pass(url)["run"]["output"]
    # analyzing again replaces results: refused until confirmed, the list is always allowed
    X0 = W.read_index(res)
    code, j = _json(run, {"options": again})
    assert code == 400 and j["code"] == "again" and "replaces their results" in j["error"]
    code, j = _json(run, {"options": {"reanalyze": "outdated"}})
    assert code == 400 and j["code"] == "again"
    assert len(_json(url + "/api/watcher")[1]["reports"]) == 1
    time.sleep(1.1)   # the time of the analysis in the index has seconds
    code, j = _json(run, {"options": again, "again": True})
    assert code == 200 and j["started"]
    w = _wait_pass(url)
    assert w["run"]["error"] == "" and not w["run"]["dry_run"] and "watcher report" in w["run"]["report"]
    assert len(w["reports"]) == 2 and w["counts"] == {"ok": 1}
    X1 = W.read_index(res)
    assert list(X1["status"]) == ["ok"] and X1["analyzed"][0] > X0["analyzed"][0]
    code, j = _json(url + "/api/results")
    assert code == 200 and j["missing"] == [] and len(j["rows"]) >= 1   # flags of the new analysis are there
