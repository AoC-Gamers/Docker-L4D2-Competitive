"""Real coverage.py + Bash + a Python child, in an isolated miniature checkout."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import make_sonar as sonar


class PythonSubprocessMeasurement(unittest.TestCase):
    def test_child_execution_is_measured_and_unexecuted_lines_remain_missing(self):
        import coverage
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root/'.gitignore').write_text('reports/\n')
            (root/'.coveragerc').write_text((sonar.ROOT/'.coveragerc').read_text())
            (root/'child.py').write_text('''def choose(value):
    if value:
        return "executed"
    return "not executed"
print(choose(True))
''')
            (root/'scripts').mkdir()
            (root/'scripts/test-stack.sh').write_text('#!/bin/bash\nset -euo pipefail\npython3 child.py\n')
            with patch.object(sonar, 'ROOT', root), patch.object(sonar, 'REPORTS', root/'reports'):
                receipt = sonar.collect_coverage()
            report = json.loads((root/receipt['coveragePath']).with_suffix('.json').read_text())
            child = report['files']['child.py']
            self.assertIn(3, child['executed_lines'])
            self.assertIn(4, child['missing_lines'])
            self.assertGreater(child['summary']['num_partial_branches'], 0)
            self.assertEqual(set(report['files']), {'child.py'})
