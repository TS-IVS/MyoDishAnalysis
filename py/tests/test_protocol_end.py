# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""End of protocols without end comment (find_protocols, regular_pacing_start) with a synthetic recording (9 channels,
400 Hz, 2400 s; stimuli of channels 1 and 2 in the status channel). Pendant of mda_testProtocolEnd.m.

       0- 300 s  0.5 Hz, 60 mA (regular)
     300 s       'start stimCurrent threshold protocol': current steps 20, 30, 40, 50, 70, 80 mA every 40 s
     540- 1000   0.5 Hz, 60 mA                    --> ST ends at 540 s (regular pacing)
    1000 s       'start post rest potentiation protocol': 3 trains of 10 stimuli (0.5 Hz), 30 s pauses
    1150 s       'start FFR protocol': 1 Hz, 2 Hz (100 s each)   --> PRP ends at 1150 s (next protocol)
    1350- 2400   0.5 Hz, 60 mA                    --> FFR ends at 1350 s (regular pacing)
    1800 s       'start pulse duration protocol': pulse duration (log chargeDuration) 1000, 500, 250, 2000 us
                 every 30 s, interval and current unchanged   --> PD ends at 1890 s (pulse duration unchanged)

Structured events of the control software (log_events) and protocols from protocolRun events (2026-10-18): the same
recording with a log as written by the control software (UTF-16 with byte order mark, CRLF, JSON values; invented
session and values):

    waiting   user; protocol 'pre-run' (start and end before the recording: not listed); start of 'wash in'
       0 s    LogFile created / opened, recording started, logOpen, slice_state (ch 1, 2)
     200 s    end of 'wash in' (substance)                  --> 0 ... 200 s, started before this recording
     300 s    ST 'stim threshold' from a schedule file      --> 300 ... 540 s (automatic comments not read again)
    1000 s    comment 'start post rest potentiation protocol' (written by the schedule file itself)
    1002 s    PRP 'PRP 30 s', aborted by the user at 1150 s --> 1002 ... 1150 s, the comment protocol is dropped
    1150 s    comment 'start FFR protocol' (no protocolRun) --> 1150 ... 1350 s (end estimated as before)
    1800 s    doseResponse 'iso DRC' by hand, no end        --> 1800 ... 2400 s (end of the file)
    1900 s    a JSON line cut off (counted, left out); a comment starting with '{' (no structured line)

Example event logs of the control software (py/tests/event_logs_2_2, see its README; 2026-10-20): waiting lines
(also of a file first written as second recording, a new run of the program, the time of the opening that follows),
pairing of the automatic comments with the next protocolRun line, the new codes chamber, rigor and backup.

TS 2026-10-10 (protocolRun events 2026-10-18; example logs of the control software 2026-10-20)
"""
import glob
import json
import math
import os

import numpy as np

import myodish_analysis as mda
from myodish_analysis.log_entries import log_entries, log_events
from myodish_analysis.protocols import auto_comments

EV_LOGS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "event_logs_2_2")

FS = 400
T = 2400


def stimuli():
    """times (s) and currents (mA) of the stimuli"""
    t, cur = [], []
    steps = [20, 30, 40, 50, 70, 80]
    for x in np.arange(0, 1000, 2.0):  # 0.5 Hz, ST current steps
        t.append(x)
        cur.append(steps[int((x - 300) // 40)] if 300 <= x < 540 else 60)
    for a in (1000, 1050, 1100):  # PRP trains
        for i in range(10):
            t.append(a + 2.0 * i); cur.append(60)
    for x in np.arange(1150, 1250, 1.0):
        t.append(x); cur.append(60)
    for x in np.arange(1250, 1350, 0.5):
        t.append(x); cur.append(60)
    for x in np.arange(1350, T - 1, 2.0):
        t.append(x); cur.append(60)
    return np.array(t), np.array(cur)


def write_recording(f, rows=None):
    n = T * FS
    x = np.zeros((9, n), dtype="<i2")
    x[:8] = -383
    t, cur = stimuli()
    for c in (1, 2):  # pulse of channel c one sample after the one of channel c-1
        idx = np.round(t * FS).astype(int) + (c - 1)
        x[8, idx] = (cur.astype(int) | (c << 9)).astype("<i2")
    x.T.tofile(f)
    name = f.replace("\\", "/").rsplit("/", 1)[-1]
    head = [(0, 0, "samplingRate Recording", "400"), (0, 0, "Recording", "started: " + name),
            (0, 0, "chargeDuration", "2000")]
    if rows is not None:
        rows = head + rows + [(T, 0, "Recording", "stopped: " + name)]
    else:
        rows = [(0, 0, "samplingRate Recording", "400"), (0, 0, "Recording", "started: " + name),
                (0, 0, "chargeDuration", "2000"),
                (300, 0, "comment", "start stimCurrent threshold protocol"),
                (1000, 0, "comment", "start post rest potentiation protocol"),
                (1150, 0, "comment", "start FFR protocol"),
                (1800, 0, "comment", "start pulse duration protocol"),
                (1800, 0, "chargeDuration", "1000"), (1830, 0, "chargeDuration", "500"),
                (1860, 0, "chargeDuration", "250"), (1890, 0, "chargeDuration", "2000"),
                (T, 0, "Recording", "stopped: " + name)]
    lines = ["systemTime;dataLogTime;channel;code;value"]
    for s, ch, code, val in rows:
        hh, mm, ss = 10 + s // 3600, (s % 3600) // 60, s % 60
        lines.append(f"2000 01 01 {hh:02d}:{mm:02d}:{ss:02d}:000;{s * 1000};{ch};{code};{val}")
    with open(f[:-4] + "_log.log", "w") as fh:
        fh.write("\n".join(lines) + "\n")


def test_protocol_end_estimated(tmp_path):
    f = str(tmp_path / "pend_rigA_0.mdd")
    write_recording(f)
    P = mda.find_protocols(f)
    assert P["type"].tolist() == ["ST", "PRP", "FFR", "PD"]
    np.testing.assert_allclose(P["from"], [300, 1000, 1150, 1800])
    np.testing.assert_allclose(P["to"], [540, 1150, 1350, 1890])
    assert P["note"][0] == "no end comment: end estimated at 540 s (start of regular pacing: 0.5 Hz, 60 mA, > 5 min)"
    assert P["note"][1] == ("no end comment: end estimated at 1150 s (start of the next protocol 'FFR protocol')")
    assert P["note"][2] == "no end comment: end estimated at 1350 s (start of regular pacing: 0.5 Hz, 60 mA, > 5 min)"
    assert P["note"][3] == "no end comment: end estimated at 1890 s (start of regular pacing: 0.5 Hz, 60 mA, > 5 min)"
    # log file only (no stimuli): next protocol or end of the file
    L = mda.find_protocols(f[:-4] + "_log.log")
    np.testing.assert_allclose(L["to"][:3], [1000, 1150, 1800])
    assert math.isinf(L["to"][3]) and L["note"][3] == "no end comment: end estimated at Inf s (end of the file)"
    # without the end estimation from the stimuli
    P0 = mda.find_protocols(f, regular_minutes=0)
    np.testing.assert_allclose(P0["to"], [1000, 1150, 1800, T])
    assert P0["note"][3] == f"no end comment: end estimated at {T} s (end of the file)"


def test_protocol_keywords_and_interruptions(tmp_path):
    """comments without protocol keyword are no protocol; 'StimThresh' = ST; a protocol of unknown type needs an end
    comment or regular pacing; a software restart ends a protocol without end comment, a connection lost for 1 s does
    not (2026-10-11)"""
    f = str(tmp_path / "pkw_rigA_0.mdd")
    write_recording(f, [(100, 0, "comment", "Software new started"),
                        (300, 0, "comment", "Start StimThresh"),
                        (600, 0, "comment", "not sure if stim protocol started"),
                        (1000, 0, "comment", "start post rest potentiation protocol"),
                        (1150, 0, "comment", "start FFR protocol"),
                        (1200, 0, "event", "Connection lost"), (1201, 0, "event", "Connection re-established"),
                        (1250, 0, "Event", "LogFile opened: C:/x/pkw_rigA_0_log.log"),
                        (1250, 0, "programInfo", "Version 2.0.1"),
                        (1800, 0, "comment", "start training programme"),
                        (1830, 0, "comment", "end of training programme"),
                        (2100, 0, "event", "Connection lost")])
    P = mda.find_protocols(f)
    assert P["type"].tolist() == ["ST", "PRP", "FFR", "unknown"]
    np.testing.assert_allclose(P["from"], [300, 1000, 1150, 1800])
    np.testing.assert_allclose(P["to"], [540, 1150, 1250, 1830])
    assert P["note"][2] == "no end comment: end estimated at 1250 s (software restarted)"
    assert P["groupBy"][3] == "none" and P["name"][3] == "training programme"


def test_protocols_analysed_one_by_one(tmp_path, monkeypatch):
    """a protocol outside the recorded data or with an error is not analysed (note), the others are (2026-10-11)"""
    import pandas as pd
    from myodish_analysis import analysis as an
    f = str(tmp_path / "pend_rigA_0.mdd")
    write_recording(f)
    P = mda.find_protocols(f)
    extra = P.iloc[[2]].copy()
    extra[["number", "from", "to"]] = [2.0, 2500.0, 2600.0]
    P2 = pd.concat([P, extra], ignore_index=True)
    C, S, info = mda.myodish_analysis(f, [1], protocol=P2, quiet=True)
    assert "protocol FFR 2: not analysed: outside the recorded data (2500 ... 2600 s, file length 2400.0 s)" \
        in info["notes"]
    assert list(info["rangeLabels"]) == ["ST 1", "PRP 1", "FFR 1", "PD 1"]
    assert len(info["protocols"]) == 5 and "not analysed: outside the recorded data" in info["protocols"]["note"].iloc[4]
    # an error in one protocol (here: ST): the others are analysed
    orig = an.protocol_results

    def failing(by, *a, **k):
        if by == "stimCurrent":
            raise RuntimeError("test error")
        return orig(by, *a, **k)
    monkeypatch.setattr(an, "protocol_results", failing)
    C, S, info = mda.myodish_analysis(f, [1], protocol=P, quiet=True)
    assert "protocol ST 1: not analysed: RuntimeError: test error" in info["notes"]
    assert sorted(set(S["range"])) == ["FFR 1", "PD 1", "PRP 1"]
    assert info["protocols"]["note"].iloc[0].endswith("not analysed: RuntimeError: test error")

def _j(**kw):
    return json.dumps(dict(v=1, **kw), separators=(",", ":"))


def write_dev_log(f):
    """the log of f (.mdd) as written by the control software with structured lines"""
    name = f.replace("\\", "/").rsplit("/", 1)[-1]
    rec = [(0, 0, "system", _j(event="user", actionId="S0000000AB-1", by="AB", initials="AB", name="", previous=None,
                                how="menu")),
           (0, 0, "comment", "start other protocol"),
           (0, 0, "protocolRun", _j(event="start", actionId="S0000000AB-2", by="AB", run="S0000000AB-2", type="other",
                                     name="pre-run", channels=[1, 2, 3, 4, 5, 6, 7, 8], source="manual",
                                     scheduleFile=None, line=None, timeout=60, number=1)),
           (0, 0, "comment", "end other protocol"),
           (0, 0, "protocolRun", _j(event="end", actionId="S0000000AB-3", by="AB", run="S0000000AB-2", type="other",
                                     reason="user")),
           (0, 0, "comment", "start substance protocol"),
           (0, 0, "protocolRun", _j(event="start", actionId="S0000000AB-4", by="AB", run="S0000000AB-4",
                                     type="substance", name="wash in", channels=[1, 2, 3, 4, 5, 6, 7, 8],
                                     source="manual", scheduleFile=None, line=None, timeout=3600, number=2)),
           (0, 0, "Event", "LogFile created: C:/x/" + name[:-4] + "_log.log"),
           (0, 0, "Event", "LogFile opened: C:/x/" + name[:-4] + "_log.log"),
           (0, 0, "programInfo", "Version 2.1.9787.20360"),
           (0, 0, "samplingRate Recording", "400"), (0, 0, "Recording", "started: " + name),
           (0, 0, "chargeDuration", "2000"),
           (0, 0, "system", _j(event="logOpen", actionId="S0000000AB-5", by="auto", format=2, file=name, role="main",
                                appended=False, session="S0000000AB", software="2.1.9787.20360", pc="PC", winUser="u",
                                tz="W. Europe Standard Time", utcOffset="+01:00")),
           (0, 1, "slice", _j(event="slice_state", actionId="S0000000AB-6", by="auto", kind="unknown", mount=None,
                               sliceId="", installTime="2000-01-01T09:00:00+01:00")),
           (0, 2, "slice", _j(event="slice_state", actionId="S0000000AB-6", by="auto", kind="empty")),
           (200, 0, "comment", "end substance protocol"),
           (200, 0, "protocolRun", _j(event="end", actionId="S0000000AB-7", by="AB", run="S0000000AB-4",
                                       type="substance", reason="user")),
           (300, 0, "Protocol", "#3 started (stim threshold)"),
           (300, 0, "comment", "start ST protocol"),
           (300, 0, "protocolRun", _j(event="start", actionId="S0000000AB-8", by="auto", run="S0000000AB-8", type="ST",
                                       name="stim threshold", channels=[1, 2, 3, 4, 5, 6, 7, 8], source="schedule",
                                       scheduleFile="st.txt", line=3, timeout=None, number=3)),
           (540, 0, "Protocol", "#3 ended (stim threshold)"),
           (540, 0, "comment", "end ST protocol"),
           (540, 0, "protocolRun", _j(event="end", actionId="S0000000AB-9", by="auto", run="S0000000AB-8", type="ST",
                                       reason="protocolEnd")),
           (1000, 0, "comment", "start post rest potentiation protocol"),
           (1002, 0, "comment", "start PRP protocol"),
           (1002, 0, "protocolRun", _j(event="start", actionId="S0000000AB-10", by="auto", run="S0000000AB-10",
                                        type="PRP", name="PRP 30 s", channels=[1, 2, 3, 4, 5, 6, 7, 8],
                                        source="schedule", scheduleFile="prp.txt", line=2, timeout=600, number=4)),
           (1150, 0, "comment", "end PRP protocol"),
           (1150, 0, "protocolRun", _j(event="abort", actionId="S0000000AB-11", by="AB", run="S0000000AB-10",
                                        type="PRP", reason="user")),
           (1150, 0, "comment", "start FFR protocol"),
           (1800, 0, "comment", "start doseResponse protocol"),
           (1800, 0, "protocolRun", _j(event="start", actionId="S0000000AB-12", by="AB", run="S0000000AB-12",
                                        type="doseResponse", name="iso DRC", channels=[1, 2, 3, 4, 5, 6, 7, 8],
                                        source="manual", scheduleFile=None, line=None, timeout=3600, number=5)),
           (1900, 0, "system", '{"v":1,"event":"userAction","actionId":"S0000000AB-1'),
           (1901, 0, "comment", "{not a structured line}"),
           (T, 0, "Recording", "stopped: " + name)]
    lines = ["systemTime;dataLogTime;channel;code;value"]
    for s, ch, code, val in rec:
        hh, mm, ss = 10 + s // 3600, (s % 3600) // 60, s % 60
        lines.append(f"2000 01 01 {hh:02d}:{mm:02d}:{ss:02d}:000;{s * 1000};{ch};{code};{val}")
    with open(f[:-4] + "_log.log", "wb") as fh:
        fh.write(b"\xff\xfe" + ("\r\n".join(lines) + "\r\n").encode("utf-16-le"))


def test_log_events(tmp_path):
    f = str(tmp_path / "dev_rigA_0.mdd")
    write_recording(f)
    write_dev_log(f)
    V = log_events(f[:-4] + "_log.log")
    assert V.attrs["nUnreadable"] == 1
    assert V["event"].tolist() == ["user", "start", "end", "start", "logOpen", "slice_state", "slice_state", "end",
                                   "start", "end", "start", "abort", "start"]
    assert V["waiting"].tolist() == [True] * 4 + [False] * 9
    assert V["code"].tolist()[:5] == ["system", "protocolRun", "protocolRun", "protocolRun", "system"]
    assert V["channel"].tolist()[5:7] == [1, 2] and V["data"].iloc[6] == dict(v=1, event="slice_state",
                                                                               actionId="S0000000AB-6", by="auto",
                                                                               kind="empty")
    assert V["by"].iloc[4] == "auto" and V["data"].iloc[4]["software"] == "2.1.9787.20360"
    assert V["data"].iloc[8]["scheduleFile"] == "st.txt" and V["data"].iloc[1]["scheduleFile"] is None
    # old logs: no structured lines
    write_recording(f)
    V0 = log_events(f[:-4] + "_log.log")
    assert len(V0) == 0 and V0.attrs["nUnreadable"] == 0


def test_protocols_from_protocol_run(tmp_path):
    f = str(tmp_path / "dev_rigA_0.mdd")
    write_recording(f)
    write_dev_log(f)
    P = mda.find_protocols(f)
    assert P["type"].tolist() == ["substance", "ST", "PRP", "FFR", "doseResponse"]
    assert P["name"].tolist() == ["wash in", "stim threshold", "PRP 30 s", "FFR protocol", "iso DRC"]
    np.testing.assert_allclose(P["from"], [0, 300, 1002, 1150, 1800])
    np.testing.assert_allclose(P["to"], [200, 540, 1150, 1350, T])
    assert P["groupBy"].tolist() == ["none", "stimCurrent", "pauseLength", "pacingFrequency", "none"]
    assert P["number"].tolist() == [1, 1, 1, 1, 1]
    assert P["note"].tolist() == ["started before this recording (2000-01-01 10:00:00)", "", "aborted: user",
                                  "no end comment: end estimated at 1350 s (start of regular pacing: 0.5 Hz, 60 mA, "
                                  "> 5 min)", "no end in the log: end of the file"]
    assert P["startComment"].tolist()[:3] == ["protocolRun start: wash in (manual)",
                                              "protocolRun start: stim threshold (schedule st.txt line 3)",
                                              "protocolRun start: PRP 30 s (schedule prp.txt line 2)"]
    assert P["endComment"].tolist()[:3] == ["protocolRun end: user", "protocolRun end: protocolEnd",
                                            "protocolRun abort: user"]


def test_dose_response_names(tmp_path):
    """names with dose response or the word DRC: doseResponse, tested first (as the control software)"""
    from myodish_analysis.protocols import protocol_type
    f = str(tmp_path / "drc_rigA_0.mdd")
    write_recording(f, [(100, 0, "comment", "start Iso DRC protocol"), (200, 0, "comment", "end Iso DRC protocol"),
                        (300, 0, "comment", "start dose response FFR"), (400, 0, "comment", "end dose response FFR")])
    P = mda.find_protocols(f[:-4] + "_log.log")
    assert P["type"].tolist() == ["doseResponse"] * 2 and P["groupBy"].tolist() == ["none"] * 2
    np.testing.assert_allclose(P["from"], [100, 300])
    np.testing.assert_allclose(P["to"], [200, 400])
    assert [protocol_type(x) for x in ("dose response FFR", "doseResponse", "Iso_DRC_1nM-1uM", "dose-response",
                                       "FFR", "address")] == \
        ["doseResponse", "doseResponse", "doseResponse", "doseResponse", "FFR", "other"]


def test_post_pause_keywords(tmp_path):
    """'post pause' and 'pause potentiation' are PRP keywords (2026-10-20); comments of an older standard schedule
    without end comments: each protocol ends at the start of the next one"""
    from myodish_analysis.protocols import protocol_type
    assert [protocol_type(x) for x in ("post-pause-potentiation", "Post pause potentiation", "PostPause_3-120s",
                                       "pause potentiation", "pause", "post rest")] == ["PRP"] * 4 + ["other", "PRP"]
    f = str(tmp_path / "std_rigA_0.mdd")
    write_recording(f, [(20, 0, "comment", "Start refractory period"), (1016, 0, "comment",
                                                                         "Start post-pause-potentiation"),
                        (1261, 0, "comment", "Start stimulation threshold"),
                        (1873, 0, "comment", "Start force-frequency relation")])
    P = mda.find_protocols(f[:-4] + "_log.log")
    assert P["type"].tolist() == ["RP", "PRP", "ST", "FFR"]
    assert P["groupBy"].tolist() == ["S2interval", "pauseLength", "stimCurrent", "pacingFrequency"]
    np.testing.assert_allclose(P["from"], [20, 1016, 1261, 1873])
    np.testing.assert_allclose(P["to"][:3], [1016, 1261, 1873])


def _ev(name):
    return os.path.join(EV_LOGS, *name.split("/"))


def test_event_logs_waiting_lines():
    """waiting lines (2026-10-20): LogFile2/3 count, only lines about this log, time of the opening that follows"""
    files = sorted(glob.glob(os.path.join(EV_LOGS, "*", "*_log.log")))
    assert len(files) == 26
    for f in files:
        E = log_entries(f)
        V = log_events(E)
        assert V.attrs["nUnreadable"] == 0 and len(V) > 0, f
        opens = [(i, t) for i, (c, x, t) in enumerate(zip(E["code"], E["text"], E["t_file"]))
                 if c == "Event" and str(x).startswith("LogFile") and (" opened" in x or " created" in x)]
        for r in V[V["waiting"]].itertuples():   # t_file = time of the next opening of this log
            assert r.t_file == next(t for i, t in opens if i > r.row), f
    # a file first written as the second recording, then continued as main recording: both protocols
    V = log_events(_ev("recording_callers/p_log.log"))
    assert not V["waiting"].any()
    P = mda.find_protocols(_ev("recording_callers/p_log.log"))
    assert P["name"].tolist() == ["first protocol", "second protocol"]
    np.testing.assert_allclose(P["from"], [0, 2])
    np.testing.assert_allclose(P["to"], [2, 4])
    # a whole schedule run while no recording ran (at the time of the end of another file): time of LogFile created
    V = log_events(_ev("recording_callers/c_log.log"))
    w = V[V["waiting"]]
    assert w["event"].tolist() == ["start", "reset"] and w["code"].tolist() == ["scheduleRun"] * 2
    np.testing.assert_allclose(w["t_logged"], [7.25, 7.25])
    np.testing.assert_allclose(w["t_file"], [0, 0])
    # backup lines (code backup): waiting in the log of the next recording; a new run of the program
    V = log_events(_ev("backup_update_conflict/d_00_log.log"))
    assert (V["code"].iloc[0], V["event"].iloc[0], bool(V["waiting"].iloc[0])) == ("backup", "backup_copied", True)
    assert (V["t_logged"].iloc[0], V["t_file"].iloc[0]) == (9.9, 0.0)
    V = log_events(_ev("backup_update_conflict/c_00_log.log"))
    assert V.loc[V["waiting"], "event"].tolist() == ["backup_setting", "identity", "backup_copied"]
    np.testing.assert_allclose(V.loc[V["waiting"], "t_file"], [0, 4.9, 4.9])
    # 'LogFile closed' of the main log inside a rocker stop log: no end of its session
    assert not log_events(_ev("recording_files/a_rockerStops_log.log"))["waiting"].any()


def test_event_logs_auto_comments(tmp_path):
    """automatic comments paired with the next protocolRun line of their kind and type (2026-10-20), also when the
    protocolRun line has a later dataLogTime than its comment (here + 1.5 s)"""
    src = _ev("protocol_new_form/a_log.log")
    P = mda.find_protocols(src)
    assert P["type"].tolist() == ["FFR", "ST", "PD", "other"]
    assert P["name"].tolist() == ["force frequency", "short threshold", "pulse durations", "unknown type"]
    with open(src, "rb") as fh:
        lines = fh.read().decode("utf-16").split("\r\n")
    for i, ln in enumerate(lines):
        p = ln.split(";", 4)
        if len(p) == 5 and p[3] == "protocolRun":
            p[1] = str(int(p[1]) + 1500)
            lines[i] = ";".join(p)
    f = str(tmp_path / "shifted_log.log")
    with open(f, "wb") as fh:
        fh.write(b"\xff\xfe" + "\r\n".join(lines).encode("utf-16-le"))
    E = log_entries(f)
    auto = auto_comments(E, log_events(E))
    com = E["isComment"] & E["text"].str.match(r"^(start|end) \S+ protocol$")
    assert com.sum() == 8 and auto[com.to_numpy(bool)].all() and not auto[~com.to_numpy(bool)].any()
    Q = mda.find_protocols(f)
    assert Q["name"].tolist() == P["name"].tolist()
    np.testing.assert_allclose(Q["from"], P["from"] + 1.5)

