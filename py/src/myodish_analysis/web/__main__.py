"""python -m myodish_analysis.web RESULTS [--raw RAW] [--port 8765]: the same as the command mda-web."""
from .server import main

if __name__ == "__main__":
    main()
