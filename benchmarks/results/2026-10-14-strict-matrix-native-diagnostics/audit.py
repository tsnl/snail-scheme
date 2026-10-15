#!/usr/bin/env python3
"""Cross-check complete results, frozen identities and diagnostic count scopes."""

import json
from pathlib import Path
import re

import diagnose as d


# ---- Independent representations explain the constructor totals ----


def constructor_oracle(counts):
    source = d.CASE / 'native-timing/native.native-r2n6qggl/reader.scm'
    types = [line for line in source.read_text().splitlines() if line.startswith('  (type $')]
    objects, requested, fields, written = 0, 0, 0, 0
    for tag, count in counts['types'].items():
        if int(tag) & 3 == 3:
            continue
        definition = types[(int(tag) >> 2) - 1]
        tokens = re.findall(r'\(field\s+(?:\(mut\s+)?([^\s)]+)', definition)
        widths = [dict(i8=1, i16=2, i32=4, f32=4).get(token, 8) for token in tokens]
        objects += count
        requested += count * (8 + 8 * len(tokens))
        fields += count * len(tokens)
        written += count * sum(widths)
    arrays = counts['operations']['array_new'] * 16 + counts['operations']['array_elements'] * 8
    return dict(struct_objects=objects, struct_requested=requested, struct_field_stores=fields,
                struct_field_bytes=written, array_constructor_bytes=arrays,
                total_constructor_bytes=objects * 8 + written + arrays)


def check_counters():
    first, final = d.load(d.BUILD / 'native-counters/counts.json'), d.load(d.COUNTER_RUN / 'counts.json')
    stats = d.load(d.BUILD / 'native-stats/attempt.json')['gc_statistics']
    for scope in ('setup', 'worker'):
        for category in ('functions', 'sizes', 'types'):
            d.require(first[scope][category] == final[scope][category], 'counter attempts disagree: ' + category)
        for name, value in first[scope]['operations'].items():
            d.require(final[scope]['operations'][name] == value, 'counter attempts disagree: ' + name)
        value, expected = final[scope]['operations'], constructor_oracle(final[scope])
        d.require(value['root_enter_requests'] == value['root_leave_requests'], 'root enters/leaves differ')
        d.require(value['requested_bytes'] == expected['struct_requested'] + expected['array_constructor_bytes'], 'allocation bytes differ from layouts')
        d.require(value['struct_constructor_field_stores'] == expected['struct_field_stores'], 'field-store totals differ from layouts')
        d.require(value['struct_constructor_field_bytes'] == expected['struct_field_bytes'], 'field-byte totals differ from layouts')
        d.require(value['array_constructor_bytes'] == expected['array_constructor_bytes'], 'array bytes differ')
        d.require(all(value[name] == value['allocation_requests'] for name in
                     ('bitmap_start_updates', 'allocator_header_writes', 'zero_payload_requests')), 'allocation metadata totals differ')
        d.require(value['zeroed_payload_bytes'] == value['requested_bytes'], 'zeroed/requested bytes differ')
    total = lambda name: sum(value['operations'][name] for value in final.values())
    d.require(total('allocation_requests') == stats['allocations'] and total('requested_bytes') == stats['bytes'], 'whole-process stats differ from scoped counters')
    d.require(total('gc_collections') == stats['collections'], 'GC scope counts differ')
    return dict(worker=final['worker']['operations'], constructor_oracle=constructor_oracle(final['worker']),
                whole_process_matches_original_stats=True, counter_attempts_agree=True)


# ---- All attempts retain their result and cleanup evidence ----


def check_attempts():
    checked = []
    for path in d.BUILD.glob('*/attempt.json'):
        record, directory = d.load(path), path.parent
        d.require(record['cleanup']['leader_reaped'] and record['cleanup']['live_members'] == [], 'owned process group remains')
        for field, filename in [('stdout_raw', 'stdout.bin'), ('stderr_raw', 'stderr.bin')]:
            d.require(record[field]['sha256'] == d.identity(directory / filename)['sha256'], 'capture hash differs')
        if record.get('valid_full_result'):
            stdout = (directory / 'stdout.bin').read_text()
            if directory.name.startswith('v8-code-'):
                rows = [line for line in stdout.splitlines() if line.startswith('{"seconds":')]
                d.require(len(rows) == 1, 'printed code result framing differs')
                stdout = rows[0] + '\n'
            d.validate_result({**record, 'status': 'exited'}, directory, native=directory.name.startswith('native-'), stdout=stdout)
        checked.append(dict(attempt=directory.name, returncode=record['returncode'],
                            valid_full_result=record.get('valid_full_result', False), leader_reaped=True))
    return checked


def check_erasures():
    proofs = list(d.BUILD.glob('counter-sources-*/module.proof.json'))
    for path in proofs:
        proof = d.load(path)
        target = path.parent / 'module.ll'
        erased = ''.join(line for line in target.read_text().splitlines(keepends=True) if '@matrix_diag_' not in line)
        d.require(erased.encode() == Path(proof['original']['path']).read_bytes(), 'LLVM counter erasure differs')
    source_proofs = list(d.BUILD.glob('counter-sources-*/*.c.proof.json')) + [d.BUILD / 'profile-host.proof.json']
    for path in source_proofs:
        proof = d.load(path)
        target = Path(proof['derived']['path'])
        reversed_changes = [(after, before) for before, after in reversed(proof['changes'])]
        d.require(d.replace_unique(target.read_text(), reversed_changes).encode() ==
                  Path(proof['original']['path']).read_bytes(), 'C/host counter erasure differs')
    return dict(llvm=len(proofs), c_and_host=len(source_proofs))


def sampling_summary():
    result = {}
    for label, report in [('dwarf_999_hz', 'perf-report'), ('leaf_prime_period', 'perf-leaf-report')]:
        text, rows = (d.BUILD / report / 'stdout.bin').read_text(), []
        for line in text.splitlines():
            match = re.match(r'\s*([0-9.]+)%\s+(\d+)\s+(\S+)\s+\[([.k])\]\s+(\S+)', line)
            if match:
                rows.append(dict(period_percent=float(match[1]), samples=int(match[2]), dso=match[3], mode=match[4], symbol=match[5]))
        result[label] = dict(rows=rows, samples=sum(row['samples'] for row in rows),
                             approximate_cycles=int(re.search(r'Event count \(approx\.\): (\d+)', text)[1]),
                             lost_samples=int(re.search(r'Total Lost Samples: (\d+)', text)[1]),
                             ancestry_used=False)
    d.require(result['dwarf_999_hz']['samples'] == 1908 and result['leaf_prime_period']['samples'] == 10177,
              'flat leaf sample totals differ')
    return result


# ---- Reportable checks remain effective with Python assertions disabled ----


if __name__ == '__main__':
    profile = d.summarize_profile(d.BUILD / 'v8-profile/profile.cpuprofile')
    result = dict(unchanged=d.verify_inputs(), attempts=check_attempts(), counter_checks=check_counters(),
                  llvm_erasures=check_erasures(), profile_samples=profile['samples'], clean_timing=False)
    result['native_sampling'] = sampling_summary()
    d.save(Path(__file__).with_name('checks.json'), result)
    print('Matrix diagnostic audit passed; frozen results, scopes, captures, erasures and cleanup', flush=True)
