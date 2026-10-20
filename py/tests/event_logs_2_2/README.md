# Event logs of the MyoDish Control Software (release 2.2 preview): test data

Event logs (`<name>_log.log`, UTF-16 with byte order mark, CRLF) written by the MyoDish Control Software, build 2.1
with the features of release 2.2 (protocols, slices, actions, rigor mode, chamber watch, backup copy), in its replay
test with a **simulated device**: no real recording, no tissue. Only the event logs; the data files of these runs were
synthetic and are not included. Anonymized with `py/tools/anonymize_recording.py` (dates shifted to 2000-01-01, paths
reduced to file names, PC, user, software build, controller and persons replaced by pseudonyms).

Used by `py/tests/test_protocol_end.py` and `mda_testProtocolEnd.m` (waiting lines, protocols from `protocolRun`
lines, pairing of the automatic comments, codes `chamber`, `rigor`, `backup`).

| Folder | What happens |
|---|---|
| `protocol_manual_type` | two protocols started by hand (PRP, ST); the program quits while recording (`abort`, reason `exit`) |
| `protocol_new_form` | a schedule of the new form with a loaded sub file: FFR, ST (timeout), PD ended by a `protocolEnd` of another type, type `other` |
| `protocol_cancel` | Cancel of the schedule aborts the protocol (reason `schedule`); the settings before the schedule are restored |
| `protocol_quit` | the program quits during a protocol of a schedule |
| `bug_B-38` | the program quits while the main (`a`), the second (`b`) and the rocker stop recording (`c`) run |
| `backup_update_conflict` | backup copy on; a file recorded, appended and copied; the copy line waits in the log of the next recording (`d_00`), which ends without stop lines |
| `recording_callers` | recordings started by protocols and schedules; `p_log.log`: a file first written as second recording, then continued as main recording; `c_log.log`: a whole schedule run while no recording ran |
| `recording_files` | data files in unusual situations: appended four times (once with the logging time reset to 0), the change of file close to 2 GB, all files closed without a stop, a file that cannot be opened, files closed within their first second, lines the software loses (`LogFile2/3 closed`) |

Waiting lines: lines logged while no main recording runs are written into the next main log right before its
`LogFile created/opened`; their dataLogTime is the frozen counter of the last main recording of that program run (see
the help of `mda_logEntries`).
