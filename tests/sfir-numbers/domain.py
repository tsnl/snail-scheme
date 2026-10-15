"""Independent Number cases: exact Fraction arithmetic and binary64 identities."""

from fractions import Fraction
import math
import struct


# ---- Exact answers and complete scalar observations ----


def bits(value):
    return str(struct.unpack('>Q', struct.pack('>d', value))[0])


def fixtures():
    cases = []
    def add(label, operation, a='0', b='1', value=0.0, result=0.0, text='', error=False):
        cases.append(dict(label=label, operation=operation, a=str(a), b=str(b),
                          input=bits(value), bits=bits(result), text=str(text), error=error))
    tokens = [('9223372036854775808', str(2**63)), ('#x20000000000000000', str(2**65)),
              ('4/2', '2'), ('-6/9', '-2/3'), ('#e9007199254740993.1', '90071992547409931/10'),
              ('#e0.1', '1/10'), ('#i-0/7', '-0.0'), ('1/2+3/4i', '1/2+3/4i'),
              ('1.0+0i', '1.0'), ('1+0.0i', '1.0+0.0i'), ('1-0.0i', '1.0-0.0i'),
              ('#e0@1', '0'), ('#e1/2@0', '1/2'), ('+inf.0', '+inf.0'), ('-nan.0', '+nan.0')]
    for source, text in tokens:
        add('roundtrip-' + source, 0, source, text=text)
    exacts = [Fraction(0), Fraction(2**63-1), Fraction(-2**63), Fraction(2**200+1),
              Fraction(1, 3), Fraction(-7, 2)]
    for a in exacts:
        for b in exacts:
            for operation, expected in [(1, a+b), (2, a-b), (3, a*b)]:
                add(f'exact-{operation}-{a}-{b}', operation, a, b, text=expected)
            add(f'exact-divide-{a}-{b}', 4, a, b, text=str(a/b) if b else '', error=not b)
        add(f'negate-{a}', 16, a, text=-a)
        add(f'abs-{a}', 17, a, text=abs(a))
        add(f'truncate-{a}', 7, a, text=math.trunc(a))
        add(f'numerator-{a}', 9, a, text=a.numerator)
        add(f'denominator-{a}', 10, a, text=a.denominator)
        add(f'extract-integer-{a}', 18, a, text=a.numerator, error=a.denominator != 1)
    for operation, a, b, expected in [
            (1, 2**63-1, 1, 2**63), (2, -2**63, 1, -2**63-1),
            (3, 2**62, 4, 2**64), (4, -2**63, -1, 2**63),
            (1, '1/2+3/4i', '2/3-1/4i', '7/6+1/2i'),
            (2, '1/2+3/4i', '2/3-1/4i', '-1/6+1i'),
            (3, '1/2+3/4i', '2/3-1/4i', '25/48+3/8i'),
            (4, '1/2+3/4i', '2/3-1/4i', '21/73+90/73i')]:
        add(f'promotion-or-complex-{operation}-{a}-{b}', operation, a, b, text=expected)
    for value in [0.0, -0.0, 0.1, -0.1, 5e-324, -5e-324, 1.7976931348623157e308,
                  math.inf, -math.inf, math.nan]:
        finite = math.isfinite(value)
        add(f'exact-f64-{bits(value)}', 5, value=value,
            text=str(Fraction(value)) if finite else '', error=not finite)
    for source, expected in [('9007199254740993', 2.0**53), ('9007199254740995', 2.0**53+4),
                             ('1/3', 1/3), ('-1/'+str(2**1076), -0.0), ('+inf.0', math.inf)]:
        add('inexact-' + source, 6, source, result=expected)
    for a, b in [('9007199254740993', '9007199254740992.0'), ('1/10', '0.1'),
                 ('1/2', '0.5'), (str(10**400), '+inf.0'), ('-inf.0', str(-10**400)),
                 ('-0.0', '0'), ('+inf.0', '+inf.0'), ('+nan.0', '0')]:
        def value(text):
            return float(text.replace('.0', '').replace('+inf', 'inf').replace('+nan', 'nan')) if 'inf' in text or 'nan' in text else float(text) if '.' in text else Fraction(text)
        left, right = value(a), value(b)
        expected = int(left == right) + 2*int(left < right) + 4*int(left <= right) + 8*int(left > right) + 16*int(left >= right)
        add('comparison-' + a + '-' + b, 13, a, b, result=float(expected))
    for source, expected in [('1', 31), ('1/2', 7), ('1.0', 14), ('0.5', 6),
                             ('+inf.0', 2), ('+nan.0', 2), ('1+2i', 1), ('1.0+0.0i', 14)]:
        add('predicate-' + source, 14, source, result=float(expected))
    for a, b, equal in [('1', '1/1', True), ('1', '1.0', False), ('-0.0', '0.0', False),
                        ('1', '1.0+0.0i', False), ('+nan.0', '-nan.0', True), ('2/4', '1/2', True)]:
        add('equivalent-' + a + '-' + b, 15, a, b, result=float(equal))
    for operation, source, text in [(11, '1/2+3/4i', '1/2'), (12, '1/2+3/4i', '3/4'),
                                    (12, '1.5', '0'), (12, '1-0.0i', '-0.0'),
                                    (7, '-1.5', '-1.0'), (16, '0.0', '-0.0'), (17, '-0.0', '0.0'),
                                    (9, '-0.0', '-0.0'), (10, '-0.0', '1.0'),
                                    (9, '5e-324', '1.0'), (10, '5e-324', '+inf.0'),
                                    (9, '-5e-324', '-1.0'), (10, '-5e-324', '+inf.0')]:
        add(f'projection-{operation}-{source}', operation, source, text=text)
    for source, radix, expected in [('FF', 16, '255'), ('1'+ '0'*100, 2, str(2**100)),
                                   ('7777777777777777777777', 8, str(int('7777777777777777777777', 8))),
                                   ('#x10', 2, '16')]:
        add(f'radix-{radix}-{source}', 19, source, radix, text=expected)
    for source, radix in [('102012120201', 3), ('-ZZZZZZZZZZZZZZZZZZZZ', 36),
                          ('+aBcDeFgHiJ', 20), ('0', 2), ('-000', 36)]:
        add(f'integer-radix-{radix}-{source}', 20, source, radix, text=int(source, radix))
    for source, radix in [('z', 35), ('-', 10), (' 1', 10), ('#xFF', 16), ('0', 1), ('0', 37)]:
        add(f'invalid-integer-radix-{radix}-{source}', 20, source, radix, error=True)
    for source in ['1/0', '1/-2', '#e1@1', '#e+inf.0', '1e', '123abc']:
        add('invalid-' + source, 0, source, error=True)
    add('nonreal-conversion', 6, '1+1/999999999999999999999999999999999999999i', error=True)
    add('inexact-integer-extraction', 18, '1.0', error=True)
    add('nonreal-order', 13, '1+2i', '0', error=True)
    add('zero-complex-divisor', 4, '1+2i', '0', error=True)
    return cases
