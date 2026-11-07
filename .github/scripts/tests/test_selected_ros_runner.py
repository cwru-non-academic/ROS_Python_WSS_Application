import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('selected_ros',ROOT/'.github/scripts/selected_ros_tests.py')
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
class RunnerTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
  for relative in ['conformance/test-contract.json','conformance/RosConformanceAdapter.cs','tests/ros_stubs.py',*runner.FILES]:
   target=self.root/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/relative,target)
 def mutate(self,change):
  path=self.root/'conformance/test-contract.json';value=json.loads(path.read_text());change(value);path.write_text(json.dumps(value))
  with self.assertRaises(ValueError):runner.contract(self.root)
 def test_full_inventory(self):self.assertEqual(len(runner.contract(self.root)['expected_cases']),23)
 def test_product_config(self):self.mutate(lambda v:v.update(product_root='evil'))
 def test_build_control(self):self.mutate(lambda v:v.update(adapter='.github/evil.ps1'))
 def test_extra_module(self):self.mutate(lambda v:v['test_files'].append('tests/sitecustomize.py'))
 def test_duplicate_inventory(self):self.mutate(lambda v:v['expected_cases'].append(v['expected_cases'][0]))
 def test_empty_inventory(self):self.mutate(lambda v:v.update(expected_cases=[]))
 def test_missing_adapter(self):
  (self.root/'conformance/RosConformanceAdapter.cs').unlink()
  with self.assertRaises(ValueError):runner.contract(self.root)
if __name__=='__main__':unittest.main()
