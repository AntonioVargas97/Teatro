"""Verifica reglas de la skill plantuml-diagrama-secuencia sobre archivos .puml.

Uso: python check_sequence.py <archivo.puml> [...]
Sale con código 1 si algún archivo incumple las reglas.
"""
from __future__ import annotations

import glob
import re
import sys

DECL = re.compile(
    r'^\s*(actor|boundary|control|entity|database|participant|queue|collections)\s+'
    r'(?:"[^"]*"\s+as\s+(\w+)|(\w+)(?:\s+as\s+"[^"]*")?)'
)
MSG = re.compile(
    r'^\s*(\w+)\s*(<?-{1,2}(?:>>?|\\\\|//|>x|x)?|<<?-{1,2})\s*(\w+)\s*(?:\+\+|--|\*\*|!!)?\s*(?::.*)?$'
)
OPENERS = ('alt', 'opt', 'loop', 'par', 'break', 'critical', 'group')
NEED_GUARD = ('alt', 'else', 'opt', 'break', 'loop')
NOUNS = {'boundary', 'entity', 'database'}


def check(path: str) -> list[str]:
    errors: list[str] = []
    types: dict[str, str] = {}
    depth = 0
    in_note = False
    has_autonumber = False
    with open(path, encoding='utf-8') as fh:
        lines = fh.readlines()
    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("'"):
            continue
        low = line.lower()
        if in_note:
            if low.startswith('end note') or low.startswith('endnote') or low.startswith('end ref'):
                in_note = False
            continue
        if re.match(r'^(note|hnote|rnote|ref)\b', low) and ':' not in line:
            in_note = True
            continue
        if low.startswith('autonumber'):
            has_autonumber = True
            continue
        m = DECL.match(line)
        if m:
            types[m.group(2) or m.group(3)] = m.group(1)
            continue
        word = low.split()[0]
        if word in OPENERS or word == 'else':
            if word in NEED_GUARD and not re.search(r'\[[^\]]+\]', line):
                errors.append(f'{path}:{n}: "{word}" sin guarda [condición]')
            if word in OPENERS:
                depth += 1
            elif depth == 0:
                errors.append(f'{path}:{n}: "else" fuera de fragmento')
            continue
        if low == 'end':
            depth -= 1
            if depth < 0:
                errors.append(f'{path}:{n}: "end" sin fragmento abierto')
                depth = 0
            continue
        m = MSG.match(line)
        if not m:
            continue
        a, b = m.group(1), m.group(3)
        for alias in (a, b):
            if alias not in types:
                errors.append(f'{path}:{n}: lifeline "{alias}" no declarada')
        ta, tb = types.get(a), types.get(b)
        if ta is None or tb is None or a == b:
            continue
        pair = {ta, tb}
        if 'actor' in pair and pair != {'actor', 'boundary'}:
            errors.append(f'{path}:{n}: actor solo se comunica con boundary ({a} {m.group(2)} {b})')
        if pair == {'boundary', 'entity'} or pair == {'boundary', 'database'}:
            errors.append(f'{path}:{n}: boundary no habla directo con entidad ({a} -> {b})')
        if ta == 'entity' and tb == 'entity':
            errors.append(f'{path}:{n}: entidad no envía mensajes a otra entidad ({a} -> {b})')
        if ta == 'boundary' and tb == 'boundary':
            errors.append(f'{path}:{n}: boundary no habla directo con otra boundary ({a} -> {b})')
    if depth != 0:
        errors.append(f'{path}: {depth} fragmento(s) sin "end"')
    if not has_autonumber:
        errors.append(f'{path}: falta "autonumber"')
    return errors


def main(argv: list[str]) -> int:
    files = [f for pattern in argv for f in (glob.glob(pattern) or [pattern])]
    if not files:
        print(__doc__)
        return 2
    errors = [e for f in files for e in check(f)]
    for e in errors:
        print(e)
    print('OK: reglas de secuencia cumplidas' if not errors else f'FALLO: {len(errors)} incumplimiento(s)')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
