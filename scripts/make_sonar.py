#!/usr/bin/env python3
"""Manual Sonar commands, following BanSystem/Connect's Makefile interface."""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, build_opener, HTTPRedirectHandler

from sonar_support import (SonarToolError, atomic_json, paginate, read_task,
                          source_identity, validate_origin, verify_latest, verify_task)

ROOT = Path(__file__).resolve().parent.parent
REPORTS = ROOT / 'reports'


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def context():
    values = dict(os.environ)
    path = ROOT / '.env.sonar'
    if path.is_file():
        for line in path.read_text().splitlines():
            if line.startswith(('SONAR_HOST_URL=', 'SONAR_TOKEN=')):
                key, value = line.split('=', 1)
                values.setdefault(key, value.strip().strip('\"\''))
    props = dict(line.split('=', 1) for line in (ROOT/'sonar-project.properties').read_text().splitlines()
                 if '=' in line and not line.startswith('#'))
    if any(k in props for k in ('sonar.token', 'sonar.login', 'sonar.password', 'sonar.branch.name', 'sonar.pullrequest.key')):
        raise SonarToolError('No guardar credenciales ni parametros de ramas/PR en properties.')
    token = values.get('SONAR_TOKEN', '')
    if not token:
        raise SonarToolError('Configurar SONAR_TOKEN en .env.sonar o en el entorno del host.')
    return validate_origin(values.get('SONAR_HOST_URL', '')), token, props['sonar.projectKey']


def request(base, token, path, params):
    url = base + path + '?' + urlencode(params)
    req = Request(url, headers={'Authorization': 'Bearer ' + token})
    try:
        with build_opener(NoRedirect()).open(req, timeout=30) as response:
            return json.load(response)
    except (HTTPError, URLError, ValueError):
        raise SonarToolError('Sonar API: respuesta invalida, error de acceso o conectividad.') from None


def require_develop():
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    if branch != 'develop':
        raise SonarToolError('Community: analizar solamente el checkout develop; no mezclar ramas.')


def analyze(base, token, project):
    require_develop()
    scanner = shutil.which('sonar-scanner')
    if not scanner:
        raise SonarToolError('Instalar SonarScanner CLI en el host.')
    before = source_identity(ROOT)['sha256']
    run = REPORTS / 'sonar-runs' / uuid.uuid4().hex
    run.mkdir(parents=True)
    task_path = run / 'report-task.txt'
    env = dict(os.environ, SONAR_TOKEN=token, SONAR_HOST_URL=base)
    result = subprocess.run([scanner, '-Dsonar.scanner.metadataFilePath=' + str(task_path)],
                            cwd=ROOT, env=env, capture_output=True, text=True)
    output = (result.stdout or '') + (result.stderr or '')
    for secret in (token, base64.b64encode((token + ':').encode()).decode()):
        output = output.replace(secret, '[REDACTED]')
    log = run/'scanner.log'
    log.write_text(output)
    log.chmod(0o600)
    if result.returncode:
        raise SonarToolError('Scanner fallo; revisar ' + str(log.relative_to(ROOT)))
    receipt = read_task(task_path, base, project)
    deadline = time.monotonic() + 300
    while True:
        task = request(base, token, '/api/ce/task', {'id': receipt['ceTaskId']})['task']
        verify_task(task, receipt['ceTaskId'], project)
        if task['status'] == 'SUCCESS':
            break
        if task['status'] in ('FAILED', 'CANCELED') or time.monotonic() > deadline:
            raise SonarToolError('Compute Engine fallo o excedio 300 segundos; no se confirma recibo.')
        time.sleep(2)
    gate = request(base, token, '/api/qualitygates/project_status', {'analysisId': task['analysisId']})
    verify_latest(request, base, token, project, task['analysisId'])
    if source_identity(ROOT)['sha256'] != before:
        raise SonarToolError('Fuentes cambiaron durante el analisis; repetir make sonar.')
    record = {'schema': 1, 'hostUrl': base, 'projectKey': project, 'sourceSha256': before,
              'analysisId': task['analysisId'], 'ceTaskId': task['id'], 'runId': run.name}
    atomic_json(run/'source.json', record)
    atomic_json(REPORTS/'sonar-run.json', record)
    atomic_json(REPORTS/'sonar-quality-gate.json', {**record, **gate})
    status = gate.get('projectStatus', {}).get('status')
    print(f'{project}: analisis completado; Quality Gate={status}. {base}/dashboard?id={project}')
    if status != 'OK':
        raise SonarToolError('Quality Gate no aprobado; diagnosticos conservados, sin ocultar hallazgos.')


def binding(base, token, project):
    try:
        receipt = json.loads((REPORTS/'sonar-run.json').read_text())
        if receipt['schema'] != 1 or receipt['hostUrl'] != base or receipt['projectKey'] != project:
            raise ValueError()
        if receipt['sourceSha256'] != source_identity(ROOT)['sha256']:
            raise ValueError()
        task = request(base, token, '/api/ce/task', {'id': receipt['ceTaskId']})['task']
        verify_task(task, receipt['ceTaskId'], project)
        if task['status'] != 'SUCCESS' or task['analysisId'] != receipt['analysisId']:
            raise ValueError()
        verify_latest(request, base, token, project, receipt['analysisId'])
        return receipt
    except (OSError, ValueError, KeyError, AssertionError):
        raise SonarToolError('Recibo ausente, ajeno o fuentes cambiadas; ejecutar make sonar.') from None


def report(command, base, token, project):
    receipt = binding(base, token, project)
    if command == 'issues':
        rows = paginate(request, base, token, '/api/issues/search',
                        {'componentKeys': project, 'resolved': 'false'}, 'issues', project)
        payload = {'total': len(rows), 'issues': rows}
    elif command == 'hotspots':
        rows = paginate(request, base, token, '/api/hotspots/search',
                        {'projectKey': project}, 'hotspots', project)
        payload = {'total': len(rows), 'hotspots': rows}
    else:
        metrics = ('coverage,line_coverage,branch_coverage,lines_to_cover,uncovered_lines'
                   if command == 'coverage' else 'duplicated_lines,duplicated_blocks,duplicated_files,duplicated_lines_density')
        payload = request(base, token, '/api/measures/component', {'component': project, 'metricKeys': metrics})
        if payload.get('component', {}).get('key') != project:
            raise SonarToolError('Medidas de otro proyecto.')
        payload['files'] = paginate(request, base, token, '/api/measures/component_tree',
                                   {'component': project, 'qualifiers': 'FIL', 'metricKeys': metrics}, 'components', project)
    if binding(base, token, project) != receipt:
        raise SonarToolError('Analisis cambio durante exportacion; repetir reporte.')
    atomic_json(REPORTS/f'sonar-{command}.json', {**receipt, 'complete': True, **payload})
    print(f'Reporte completo: reports/sonar-{command}.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['analyze', 'issues', 'coverage', 'duplications', 'hotspots'])
    args = parser.parse_args()
    try:
        values = context()
        if args.command == 'analyze':
            analyze(*values)
        else:
            report(args.command, *values)
    except (SonarToolError, OSError, subprocess.CalledProcessError) as error:
        print(str(error) if isinstance(error, SonarToolError) else 'Error local de herramientas; revisar instalacion.', file=__import__('sys').stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
