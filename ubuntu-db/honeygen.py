"""Generate the Ubuntu scenario from the same 100 reference customers as Windows."""
import csv
import random
import re
from pathlib import Path


def dataset(percent, seed=42):
    if not 2 <= percent <= 100:
        raise ValueError('Use an integer percentage from 2 to 100.')
    with (Path(__file__).resolve().parent / 'customers-base.csv').open() as source:
        base = [(r['CNO'], r['EMAIL'], r['FULL_NAME']) for r in csv.DictReader(source)]
    used = [set(column) for column in zip(*base)]
    if len(base) != 100 or any(len(values) != 100 for values in used):
        raise ValueError('Expected 100 unique reference customers.')
    rng = random.Random(seed + percent)
    tokens = []
    for i in range(percent):
        for attempt in range(10000):
            sample = rng.choice(base)
            prefix, family = sample[0][:3], sample[2].split()[0]
            given = rng.choice(base)[2].split()[1]
            if i < 2:
                prefix, family = [('ASN', 'Ahn'), ('YSU', 'Yun')][i]
            suffix = str(rng.randint(10, 99)) if re.search(r'\d@', rng.choice(base)[1]) else ''
            row = ('{}-{:03d}'.format(prefix, rng.randint(100, 999)),
                   (family + given).lower() + suffix + '@gmail.com', family + ' ' + given)
            if all(value not in seen for value, seen in zip(row, used)):
                tokens.append(row)
                for value, seen in zip(row, used):
                    seen.add(value)
                break
        else:
            raise ValueError('Could not generate a unique customer.')
    rows = base + tokens
    rng.shuffle(rows)
    for i in range(3):
        ordered = sorted(rows, key=lambda row: row[i])
        if (ordered[0], ordered[-1]) != tuple(tokens[:2]):
            raise ValueError('Sorted endpoints failed verification.')
    return rows, tokens


def write_seed(stream, percent):
    rows, tokens = dataset(percent)
    stream.write('COPY public.customers (cno,email,full_name) FROM STDIN WITH CSV;\n')
    writer = csv.writer(stream, lineterminator='\n')
    writer.writerows(rows)
    stream.write('\\.\nCOPY honey.tokens (cno) FROM STDIN WITH CSV;\n')
    writer.writerows((row[0],) for row in tokens)
    stream.write('\\.\n')
