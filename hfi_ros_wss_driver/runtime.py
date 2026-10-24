"""Select application-owned wrapper code before any WSS assembly is loaded."""
from __future__ import annotations

import importlib
import os
from pathlib import Path
import sys


def application_root() -> Path:
    """Locate checkout assets or the installed ROS package's share directory."""
    checkout = Path(__file__).resolve().parents[1]
    if (checkout / "package.xml").is_file():
        return checkout
    from ament_index_python.packages import get_package_share_directory

    return Path(get_package_share_directory("hfi_ros_wss_driver")).resolve()


def load_bundled_wrapper():
    """Import the selected wrapper without replacing an already imported package.

    Changing sys.path cannot safely replace Python classes or WSS assemblies
    already held by another component. In that case a fresh process is required.
    This function does not initialize a CLR or controller.
    """
    source = application_root() / "HFI_WSS_Python_Interface" / "src"
    expected = (source / "wss_py_wrapper" / "__init__.py").resolve()
    if not expected.is_file():
        raise FileNotFoundError(
            f"Bundled wrapper is missing at {expected}. Update the pinned submodule "
            "and rebuild hfi_ros_wss_driver."
        )
    loaded = sys.modules.get("wss_py_wrapper")
    for name, module in tuple(sys.modules.items()):
        if name.startswith("wss_py_wrapper.") and module is not None:
            origin = vars(module).get("__file__")
            if origin is None or not Path(origin).resolve().is_relative_to(expected.parent):
                raise RuntimeError(
                    f"Different wrapper module {name} is already imported from {origin}. "
                    "Start a fresh ROS process; wrapper replacement is unsupported."
                )
    if loaded is not None:
        actual = getattr(loaded, "__file__", None)
        if actual is None or Path(actual).resolve() != expected:
            raise RuntimeError(
                f"A different WSS wrapper is already imported from {actual}; "
                f"expected {expected}. Start a fresh ROS process; in-process "
                "wrapper/assembly replacement is unsupported."
            )
        return loaded
    # Prepend before the first import, rather than accepting a copied site-package.
    sys.path.insert(0, str(source))
    wrapper = importlib.import_module("wss_py_wrapper")
    if Path(wrapper.__file__).resolve() != expected:
        raise RuntimeError(f"Wrapper import did not select {expected}. Start a fresh process.")
    return wrapper


def selected_dll_directory(bundled: Path, explicit: Path | None = None) -> Path:
    """Honor an explicit DLL location without probing hardware or falling back."""
    selected = explicit if explicit is not None else os.environ.get("WSS_CS_LIB_DIR")
    return Path(selected).expanduser().resolve() if selected else bundled.resolve()


def reject_loaded_wss_conflict(directory: Path) -> None:
    """Require a fresh process instead of reusing WSS assemblies from elsewhere."""
    if "clr" not in sys.modules:
        return
    from System import AppDomain

    for assembly in AppDomain.CurrentDomain.GetAssemblies():
        if assembly.GetName().Name in {"WSS_Core_Interface", "WSS.Transport.Serial", "WSS.Transport.BLE"}:
            location = assembly.Location
            if not location or not Path(location).resolve().is_relative_to(directory):
                raise RuntimeError(
                    f"WSS assembly is already loaded from {location}; selected DLL "
                    f"directory is {directory}. Start a fresh ROS process; "
                    "in-process assembly replacement is unsupported."
                )
