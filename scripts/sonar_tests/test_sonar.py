import importlib.util,json,os,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import make_sonar as sonar
from sonar_support import SonarToolError,paginate,read_task,validate_origin

class SonarContract(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  self.addCleanup(self.temp.cleanup)
  self.enterContext(patch.object(sonar,'ROOT',self.root))
  self.enterContext(patch.object(sonar,'REPORTS',self.root/'reports'))
  (self.root/'sonar-project.properties').write_text('sonar.projectKey=fixture\n')
 def test_host_only_environment_and_no_evaluation(self):
  (self.root/'.env.sonar').write_text('SONAR_HOST_URL=https://sonar.invalid\nSONAR_TOKEN=opaque$(false)\nOTHER=ignored\n')
  with patch.dict(os.environ,{},clear=True):
   self.assertEqual(sonar.context(),('https://sonar.invalid','opaque$(false)','fixture'))
 def test_environment_wins(self):
  (self.root/'.env.sonar').write_text('SONAR_TOKEN=file\n')
  with patch.dict(os.environ,{'SONAR_TOKEN':'environment','SONAR_HOST_URL':'https://sonar.invalid'},clear=True):
   self.assertEqual(sonar.context()[1],'environment')
 def test_no_credentials_or_branch_in_properties(self):
  for key in ['sonar.token','sonar.branch.name','sonar.pullrequest.key']:
   (self.root/'sonar-project.properties').write_text('sonar.projectKey=fixture\n'+key+'=value\n')
   with self.assertRaises(SonarToolError):sonar.context()
 def test_only_develop_can_be_analyzed(self):
  with patch.object(sonar.subprocess,'check_output',return_value='main\n'),self.assertRaises(SonarToolError):sonar.require_develop()
 def test_unsafe_origins_rejected(self):
  for url in ['http://sonar.invalid','https://user:token@sonar.invalid','https://sonar.invalid/path','https://sonar.invalid?token=x']:
   with self.assertRaises(SonarToolError):validate_origin(url)
 def test_foreign_task_receipt_rejected(self):
  path=self.root/'task';path.write_text('projectKey=other\nserverUrl=https://sonar.invalid\nceTaskId=t1\n')
  with self.assertRaises(SonarToolError):read_task(path,'https://sonar.invalid','fixture')
 def test_duplicate_paginated_issues_rejected(self):
  payload={'paging':{'total':501},'issues':[{'key':str(i),'project':'fixture'} for i in range(500)]}
  with self.assertRaises(SonarToolError):paginate(lambda *a:payload,'https://sonar.invalid','token','/api/issues/search',{},'issues','fixture')
 def test_no_stale_report_without_receipt(self):
  with self.assertRaises(SonarToolError):sonar.binding('https://sonar.invalid','token','fixture')
