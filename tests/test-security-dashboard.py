#!/usr/bin/env python3
"""Exercise real PromQL against distinct counters with identical labels."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import yaml

root = Path(__file__).resolve().parents[1]
obj = yaml.safe_load((root / 'overlays/desenvolvimento/dashboards/service-mesh/security-dashboard.yaml').read_text())
dashboard = json.loads(obj['spec']['json'])
metrics = [
    'envoy_cluster_ssl_connection_error',
    'envoy_cluster_ssl_fail_verify_no_cert',
    'envoy_cluster_ssl_fail_verify_error',
    'envoy_listener_no_filter_chain_match',
]
tls = next(p for p in dashboard['panels'] if p['id'] == 4)
listener = next(p for p in dashboard['panels'] if p['id'] == 3)
targets = tls['targets'] + listener['targets']
assert len(targets) == 4
cases = []
for i, target in enumerate(targets):
    expr = target['expr'].replace('$namespace', 'mesh-lab').replace('$__rate_interval', '5m')
    cases.append({'expr': expr, 'eval_time': '10m', 'exp_samples': [
        {'labels': '{pod="proxy-1"}', 'value': i + 1},
    ]})
fixture = {'rule_files': [], 'evaluation_interval': '1m', 'tests': [{
    'interval': '1m',
    'input_series': [
        {'series': metric + '{namespace="mesh-lab",pod="proxy-1"}', 'values': '0+' + str((i + 1) * 60) + 'x20'}
        for i, metric in enumerate(metrics)
    ],
    'promql_expr_test': cases,
}]}
promtool = os.environ.get('PROMTOOL') or shutil.which('promtool')
if not promtool:
    raise SystemExit('BLOCKED: promtool ausente')
with tempfile.TemporaryDirectory() as temp:
    path = Path(temp) / 'series.yaml'
    path.write_text(yaml.safe_dump(fixture))
    subprocess.run([promtool, 'test', 'rules', str(path)], check=True)
print('PASS: consultas TLS e listener avaliadas com séries sintéticas')
