"""Valida dependências do bootstrap para impedir CRs antes de seu Operator."""
from pathlib import Path
import subprocess
import yaml

ROOT = Path(__file__).resolve().parents[1]
WAVE = 'argocd.argoproj.io/sync-wave'


def wave(obj):
    return int(obj.get('metadata', {}).get('annotations', {}).get(WAVE, '0'))


def validate(objects):
    subscriptions = [o for o in objects if o['kind'] == 'Subscription' and o['metadata']['name'] == 'grafana-operator']
    assert len(subscriptions) == 1, 'Subscription Grafana ausente ou duplicada'
    operator_wave = wave(subscriptions[0])
    resources = [o for o in objects if o['apiVersion'].startswith('grafana.integreatly.org/')]
    folders = {o['metadata']['name']: o for o in resources if o['kind'] == 'GrafanaFolder'}
    for obj in resources:
        name = obj['metadata']['name']
        assert wave(obj) > operator_wave, f'{obj["kind"]}/{name} antecede a instalação do Operator'
        if obj['kind'] == 'GrafanaDashboard' and obj.get('spec', {}).get('folderRef'):
            folder = obj['spec']['folderRef']
            assert folder in folders, f'Pasta {folder} não declarada'
            assert wave(obj) > wave(folders[folder]), f'Dashboard {name} não está após sua pasta'
    return resources


for environment in ('desenvolvimento', 'aceite', 'producao'):
    result = subprocess.check_output(['kubectl', 'kustomize', str(ROOT / 'overlays' / environment)], text=True)
    objects = [o for o in yaml.safe_load_all(result) if o]
    resources = validate(objects)
    # Reproduz a omissão que colocava o dashboard na wave zero de uma instalação nova.
    broken = yaml.safe_load(yaml.safe_dump(objects))
    target = next(o for o in broken if o['kind'] == 'GrafanaDashboard')
    target['metadata'].setdefault('annotations', {}).pop(WAVE, None)
    try:
        validate(broken)
    except AssertionError:
        pass
    else:
        raise AssertionError('Regressão sem wave não foi detectada')
    print(f'PASS: {environment}, {len(resources)} recursos Grafana e regressão de wave ausente')
