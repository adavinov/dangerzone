import os
import sys

try:
    from . import vendor  # type: ignore [attr-defined]

    vendor_path: str = vendor.__path__[0]
    print(f"Using vendored PyMuPDF libraries from '{vendor_path}'", file=sys.stderr)
    sys.path.insert(0, vendor_path)
except ImportError:
    pass

if "DANGERZONE_MODE" in os.environ:
    mode = os.environ["DANGERZONE_MODE"]
else:
    basename = os.path.basename(sys.argv[0])
    if basename == "dangerzone-cli" or basename == "dangerzone-cli.exe":
        mode = "cli"
    else:
        mode = "gui"

if mode == "cli":
    from .cli import cli_main as main
else:
    from .gui import gui_main as main  # noqa: F401
