"""Collect phase counters separately from the rotating timing series."""
import json
import os

import measure


def main():
    cases = [
        ('precise300', None), ('nursery8', None), ('nursery32', None),
        ('immix', None), ('precise300', 128), ('nursery8', 128),
        ('immix', 128),
    ]
    report = dict(complete=False, samples=[])
    os.environ['SNAIL_GC_STATS'] = '1'
    for variant, minimum_mib in cases:
        os.environ.pop('SNAIL_GC_MIN_BYTES', None)
        if minimum_mib:
            os.environ['SNAIL_GC_MIN_BYTES'] = str(minimum_mib << 20)
        value = measure.sample('compiler', variant)
        value.update(variant=variant, minimum_budget_mib=minimum_mib)
        report['samples'].append(value)
        (measure.BUILD / 'diagnostics.json').write_text(json.dumps(report, indent=2) + '\n')
        print(variant, minimum_mib, value['seconds'], value['stderr'].strip(), flush=True)
    report['complete'] = True
    (measure.BUILD / 'diagnostics.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
