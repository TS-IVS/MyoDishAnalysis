"""MyoDishAnalysis (Python): contraction parameters of every single contraction in MyoDish recordings (.mdd).

Port of the MATLAB MyoDishAnalysis (T. Seidel, FAU Erlangen-Nuernberg / InVitroSys GmbH); the MATLAB version is
the reference. Module names follow the MATLAB files (mda_readMdd --> read_mdd, mda_analyzeChannel -->
analyze_channel, ...); option names, column names and units are the same as in MATLAB.

    from myodish_analysis import myodish_analysis, read_mdd, analyze_channel, options
    contractions, summary, info = myodish_analysis('examples/example3_humanVentricle.mdd', 6, 0, 120)

Command line: mda (analysis), mda-gui (interactive), mda-watch (new recordings of a folder), mda-test (self test).

TS 2026-10-06
"""
__version__ = "1.0.0b1"

from .options import options  # noqa: E402
from .parameters import parameters, PARAMETERS, LABEL_NAMES  # noqa: E402
from .read_mdd import read_mdd, read_header, read_data, read_overview  # noqa: E402
from .log_entries import log_entries  # noqa: E402
from .calibration_factor import calibration_factor  # noqa: E402
from .zero_force import zero_force  # noqa: E402
from .analyze_channel import analyze_channel  # noqa: E402
from .rocker_filter import rocker_filter  # noqa: E402
from . import reference_beat  # noqa: E402
from .read_ep_recording import read_ep_recording  # noqa: E402
from .analyze_ap import analyze_ap, AP_PARAMETERS  # noqa: E402
from .summarize import summarize  # noqa: E402
from .write_results import write_results  # noqa: E402
from .labels import labels  # noqa: E402
from .add_labels import add_labels  # noqa: E402
from .analysis import myodish_analysis  # noqa: E402
from .protocols import find_protocols, group_beats  # noqa: E402
from .protocol_results import protocol_results  # noqa: E402
from .selftest import selftest  # noqa: E402
from .watch import watch  # noqa: E402

__all__ = ["options", "parameters", "PARAMETERS", "LABEL_NAMES", "read_mdd", "read_header", "read_data",
           "read_overview", "log_entries", "calibration_factor", "zero_force", "analyze_channel", "rocker_filter",
           "reference_beat", "read_ep_recording", "analyze_ap", "AP_PARAMETERS", "summarize", "write_results",
           "labels", "add_labels", "myodish_analysis", "find_protocols", "group_beats", "protocol_results", "selftest", "watch", "__version__"]
