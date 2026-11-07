import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
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
 def execute_inventory(self, mode):
  app=self.root/'app';(app/'tests').mkdir(parents=True)
  expected=[]
  for index, relative in enumerate(runner.FILES):
   decorator='@unittest.skip("forbidden skip")\n ' if mode=='skip' and index==0 else ''
   assertion='self.fail("fixture failure")' if mode=='failure' and index==0 else 'self.assertTrue(True)'
   (app/relative).write_text('import unittest\nclass Cases(unittest.TestCase):\n '+decorator+'def test_case(self): '+assertion+'\n')
   expected.append(Path(relative).stem+'.Cases.test_case')
  if mode=='missing':expected.pop()
  command='import importlib.util,json;from pathlib import Path;s=importlib.util.spec_from_file_location("runner",'+repr(str(ROOT/'.github/scripts/selected_ros_tests.py'))+');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.run(Path('+repr(str(app))+'),'+repr(expected)+',Path('+repr(str(self.root/'result.json'))+'))'
  result=subprocess.run([sys.executable,'-I','-B','-c',command],capture_output=True,text=True)
  self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
  self.assertFalse((self.root/'result.json').exists())
 def test_reject_runtime_skip(self):self.execute_inventory('skip')
 def test_reject_missing_runtime_inventory(self):self.execute_inventory('missing')
 def test_reject_runtime_failure(self):self.execute_inventory('failure')
if __name__=='__main__':unittest.main()
