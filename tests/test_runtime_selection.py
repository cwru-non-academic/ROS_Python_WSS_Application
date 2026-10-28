"""Test import selection in fresh interpreters without loading a CLR."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RuntimeSelectionTests(unittest.TestCase):
    def execute(self, script, *arguments, cwd=None):
        env = dict(os.environ)
        env.pop("WSS_CS_LIB_DIR", None)
        result = subprocess.run([sys.executable, "-c", script, str(ROOT), *map(str, arguments)], cwd=cwd or ROOT, env=env, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unimported_copied_install_cannot_shadow_bundled_source(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "wss_py_wrapper"
            package.mkdir()
            (package / "__init__.py").write_text("raise AssertionError('External package executed')\n")
            self.execute("""
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[2])
from hfi_ros_wss_driver.runtime import load_bundled_wrapper
wrapper = load_bundled_wrapper()
assert Path(wrapper.__file__).resolve() == Path(sys.argv[1], 'HFI_WSS_Python_Interface/src/wss_py_wrapper/__init__.py').resolve()
assert 'clr' not in sys.modules and 'pythonnet' not in sys.modules
assert load_bundled_wrapper() is wrapper
""", directory)

    def test_already_imported_other_wrapper_requires_restart(self):
        self.execute("""
import sys, types
from hfi_ros_wss_driver.runtime import load_bundled_wrapper
other = types.ModuleType('wss_py_wrapper'); other.__file__ = '/external/wss_py_wrapper/__init__.py'
sys.modules['wss_py_wrapper'] = other
try: load_bundled_wrapper()
except RuntimeError as exc: assert 'fresh ROS process' in str(exc)
else: raise AssertionError('A loaded package was replaced')
assert sys.modules['wss_py_wrapper'] is other
assert 'clr' not in sys.modules
""")

    def test_installed_layout_uses_share_assets_without_source_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            site = root / "site"
            share = root / "share" / "hfi_ros_wss_driver"
            shutil.copytree(ROOT / "hfi_ros_wss_driver", site / "hfi_ros_wss_driver", ignore=shutil.ignore_patterns("__pycache__"))
            shutil.copytree(ROOT / "HFI_WSS_Python_Interface" / "src" / "wss_py_wrapper", share / "HFI_WSS_Python_Interface" / "src" / "wss_py_wrapper", ignore=shutil.ignore_patterns("__pycache__"))
            self.execute("""
import sys, types
from pathlib import Path
sys.path = [sys.argv[2]] + [p for p in sys.path if p not in ('', sys.argv[1])]
ament = types.ModuleType('ament_index_python'); packages = types.ModuleType('ament_index_python.packages')
packages.get_package_share_directory = lambda name: sys.argv[3]
sys.modules['ament_index_python'] = ament; sys.modules['ament_index_python.packages'] = packages
from hfi_ros_wss_driver.runtime import application_root, load_bundled_wrapper
assert application_root() == Path(sys.argv[3]).resolve()
wrapper = load_bundled_wrapper()
assert Path(wrapper.__file__).resolve().is_relative_to(Path(sys.argv[3]).resolve())
assert 'clr' not in sys.modules
""", site, share, cwd=root)

    def test_stale_partial_python_import_requires_restart(self):
        self.execute("""
import sys, types
from hfi_ros_wss_driver.runtime import load_bundled_wrapper
other = types.ModuleType('wss_py_wrapper.config'); other.__file__ = '/external/config.py'
sys.modules[other.__name__] = other
try: load_bundled_wrapper()
except RuntimeError as exc: assert 'fresh ROS process' in str(exc)
else: raise AssertionError('Stale child module was reused')
""")

    def test_loaded_wss_assembly_from_another_directory_requires_restart(self):
        self.execute("""
import sys, types
from pathlib import Path
from hfi_ros_wss_driver.runtime import reject_loaded_wss_conflict
reject_loaded_wss_conflict(Path('selected').resolve())
sys.modules['clr'] = types.ModuleType('clr')
assembly = types.SimpleNamespace(Location=str(Path('different/WSS_Core_Interface.dll').resolve()), GetName=lambda: types.SimpleNamespace(Name='WSS_Core_Interface'))
system = types.ModuleType('System')
system.AppDomain = types.SimpleNamespace(CurrentDomain=types.SimpleNamespace(GetAssemblies=lambda: [assembly]))
sys.modules['System'] = system
try: reject_loaded_wss_conflict(Path('selected').resolve())
except RuntimeError as exc: assert 'fresh ROS process' in str(exc)
else: raise AssertionError('A loaded WSS assembly was replaced')
assembly.Location = str(Path('selected/WSS_Core_Interface.dll').resolve())
reject_loaded_wss_conflict(Path('selected').resolve())
""")

    def test_external_dll_selection_is_honored_without_fallback(self):
        self.execute("""
import os, sys
from pathlib import Path
from hfi_ros_wss_driver.runtime import selected_dll_directory
bundled = Path('bundled')
assert selected_dll_directory(bundled) == bundled.resolve()
os.environ['WSS_CS_LIB_DIR'] = 'deliberate-external'
assert selected_dll_directory(bundled) == Path('deliberate-external').resolve()
assert selected_dll_directory(bundled, Path('constructor-choice')) == Path('constructor-choice').resolve()
assert 'clr' not in sys.modules
""")


if __name__ == "__main__":
    unittest.main()
