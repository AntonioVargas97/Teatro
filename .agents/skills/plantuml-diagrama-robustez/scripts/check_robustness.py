"""Verifica reglas ICONIX (sustantivo-verbo) en diagramas de robustez PlantUML.

Uso: python check_robustness.py <archivo.puml> [...]
Sale con código 1 si algún archivo incumple las reglas.
"""
from __future__ import annotations

import glob
import re
import sys

DECL = re.compile(
    r'^\s*(actor|boundary|control|entity)\s+'
    r'(?:"[^"]*"\s+as\s+(\w+)|(\w+)(?:\s+as\s+"[^"]*")?)'
)
LINK = re.compile(
    r'^\s*(\w+)\s+(<?[-.]+(?:\[[^\]]*\])?(?:left|right|up|down|le|ri|do)?[-.]*>?)\s+(\w+)\s*(?::.*)?$'
)
ALLOWED = {
    frozenset({'actor', 'boundary'}),
    frozenset({'boundary', 'control'}),
    frozenset({'control'}),
    frozenset({'control', 'entity'}),
}


def check(path: str) -> list[str]:
    errors: list[str] = []
    types: dict[str, str] = {}
    degree: dict[str, int] = {}
    boundary_controls: dict[str, int] = {}
    with open(path, encoding='utf-8') as fh:
        lines = fh.readlines()
    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("'"):
            continue
        m = DECL.match(line)
        if m:
            alias = m.group(2) or m.group(3)
            types[alias] = m.group(1)
            degree.setdefault(alias, 0)
            continue
        m = LINK.match(line)
        if not m or 'hidden' in m.group(2):
            continue
        a, b = m.group(1), m.group(3)
        missing = [x for x in (a, b) if x not in types]
        if missing:
            errors.append(f'{path}:{n}: alias no declarado {missing}')
            continue
        ta, tb = types[a], types[b]
        if frozenset({ta, tb}) not in ALLOWED:
            errors.append(f'{path}:{n}: conexión prohibida {ta} "{a}" -- {tb} "{b}"')
        degree[a] += 1
        degree[b] += 1
        for x, tx, ty in ((a, ta, tb), (b, tb, ta)):
            if tx == 'boundary' and ty == 'control':
                boundary_controls[x] = boundary_controls.get(x, 0) + 1
    for alias, d in degree.items():
        if d == 0:
            errors.append(f'{path}: elemento huérfano "{alias}" ({types[alias]})')
        if types[alias] == 'boundary' and not boundary_controls.get(alias):
            errors.append(f'{path}: boundary "{alias}" sin control asociado')
    if not any(t == 'control' for t in types.values()):
        errors.append(f'{path}: no hay controles')
    return errors


def main(argv: list[str]) -> int:
    files = [f for pattern in argv for f in (glob.glob(pattern) or [pattern])]
    if not files:
        print(__doc__)
        return 2
    errors = [e for f in files for e in check(f)]
    for e in errors:
        print(e)
    print('OK: reglas de robustez cumplidas' if not errors else f'FALLO: {len(errors)} incumplimiento(s)')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
