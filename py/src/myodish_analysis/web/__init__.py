# MyoDishAnalysis (https://github.com/TS-IVS/MyoDishAnalysis)
# Copyright (c) 2026 Thomas Seidel
# SPDX-License-Identifier: GPL-3.0-or-later
# Additional terms (GPL-3.0 section 7): see the file NOTICE
"""MyoDishAnalysis in the browser: see server.py (mda-web RESULTS)."""
from .server import App, main, make_server, serve

__all__ = ["App", "main", "make_server", "serve"]
