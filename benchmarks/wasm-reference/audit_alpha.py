"""Compare complete residual programs while preserving lexical binding meaning."""

import re
import unittest

# ---- Serialized residual programs ----


def read_program(text):
    tokens = iter(re.findall(r'"(?:\\.|[^"\\])*"|[()]|[^()\s]+', text))
    result = read_term(next(tokens), tokens)
    if next(tokens, None) is not None:
        raise ValueError("extra audit datum")
    return result


def read_term(token, tokens):
    if token != "(":
        if token == ")":
            raise ValueError("unexpected audit delimiter")
        return token
    result = []
    while (token := next(tokens)) != ")":
        result.append(read_term(token, tokens))
    return result


# ---- Lexical alpha equivalence without renaming quoted or free symbols ----


def canonical_program(expression, environment, serial):
    if not isinstance(expression, list):
        return environment.get(expression, expression)
    if not expression or expression[0] == "quote":
        return expression
    if expression[0] in ("lambda", "let", "letrec") and len(expression) < 3:
        raise ValueError("audit binding form requires a body")
    if expression[0] == "lambda":
        names, nested = bind_names(expression[1], environment, serial)
        body = [canonical_program(item, nested, serial) for item in expression[2:]]
        return ["lambda", names, *body]
    if expression[0] in ("let", "letrec"):
        return canonical_binding(expression, environment, serial)
    return [canonical_program(item, environment, serial) for item in expression]


def bind_names(names, environment, serial):
    if not isinstance(names, list) or not all(is_identifier(name) for name in names):
        raise ValueError("audit binders must be a proper identifier list")
    if len(set(names)) != len(names):
        raise ValueError("duplicate audit binder")
    nested, renamed = dict(environment), []
    for name in names:
        identity = ("bound variable", serial[0])
        serial[0] += 1
        nested[name] = identity
        renamed.append(identity)
    return renamed, nested


def is_identifier(token):
    # The residual grammar has ordinary symbols, fixed parameter lists, and
    # serialized literals. It does not include escaped or dotted binders.
    return (isinstance(token, str) and token not in ("", ".")
            and not re.match(r'[#"]|[+-]?(?:\d|\.\d)', token))


def canonical_binding(expression, environment, serial):
    bindings = expression[1]
    if not isinstance(bindings, list) or not all(isinstance(entry, list) and len(entry) == 2 for entry in bindings):
        raise ValueError("audit binding must contain one name and initializer")
    names, nested = bind_names([entry[0] for entry in bindings], environment, serial)
    values_env = nested if expression[0] == "letrec" else environment
    entries = [[name, canonical_program(entry[1], values_env, serial)]
               for name, entry in zip(names, bindings)]
    body = [canonical_program(item, nested, serial) for item in expression[2:]]
    return [expression[0], entries, *body]


def alpha_equivalent(first, second):
    try:
        return canonical_program(read_program(first), {}, [0]) == canonical_program(read_program(second), {}, [0])
    except (ValueError, StopIteration):
        return False


# ---- Tests ----


class AlphaAuditTests(unittest.TestCase):
    def test_nested_shadowing_and_recursive_bindings(self):
        self.assertTrue(alpha_equivalent("(lambda (x) (let ((x x)) x))",
                                         "(lambda (a) (let ((b a)) b))"))
        self.assertTrue(alpha_equivalent("(letrec ((f (lambda (x) (f x)))) (f y))",
                                         "(letrec ((g (lambda (a) (g a)))) (g y))"))

    def test_free_symbols_literals_and_capture_remain_distinct(self):
        self.assertFalse(alpha_equivalent("(lambda (x) (quote x))", "(lambda (a) (quote a))"))
        self.assertFalse(alpha_equivalent("(lambda (x) y)", "(lambda (a) z)"))
        self.assertFalse(alpha_equivalent("(lambda (x) (let ((x x)) x))",
                                          "(lambda (a) (let ((b a)) a))"))
        self.assertFalse(alpha_equivalent("(lambda (x) (lambda (y) x))",
                                          "(lambda (a) (lambda (a) a))"))
        self.assertFalse(alpha_equivalent("(lambda (x y) (pair x y))",
                                          "(lambda (a b) (pair b a))"))

    def test_every_body_expression_is_compared_in_order(self):
        for head, renamed in (("lambda (x)", "lambda (a)"),
                              ("let ((x 1))", "let ((a 1))"),
                              ("letrec ((x 1))", "letrec ((a 1))")):
            with self.subTest(form=head):
                original = f"({head} x (quote end))"
                self.assertTrue(alpha_equivalent(original, f"({renamed} a (quote end))"))
                for body in ("a", "a (quote end) a", "a (quote changed)", "(quote end) a"):
                    self.assertFalse(alpha_equivalent(original, f"({renamed} {body})"))

    def test_initializer_and_body_scopes(self):
        self.assertTrue(alpha_equivalent("(lambda (x) (let ((x x)) x x))",
                                         "(lambda (a) (let ((b a)) b b))"))
        self.assertFalse(alpha_equivalent("(lambda (x) (let ((x x)) x x))",
                                          "(lambda (a) (let ((b b)) b b))"))
        self.assertTrue(alpha_equivalent("(letrec ((f (lambda () f))) f f)",
                                         "(letrec ((g (lambda () g))) g g)"))
        self.assertFalse(alpha_equivalent("(letrec ((f (lambda () f))) f f)",
                                          "(letrec ((g (lambda () f))) g g)"))

    def test_malformed_binders_and_bodies_cannot_pass(self):
        cases = (("(lambda (x x) x)", "(lambda (a b) b)"),
                 ("(lambda (1) 1)", "(lambda (a) a)"),
                 ("(lambda x x)", "(lambda (a) a)"),
                 ("(lambda (x . y) x)", "(lambda (a b c) a)"),
                 ("(let ((x 1) (x 2)) x)", "(let ((a 1) (b 2)) b)"),
                 ("(let ((x 1 2)) x)", "(let ((a 1)) a)"),
                 ("(letrec ((x 1 2)) x)", "(letrec ((a 1)) a)"),
                 ("(lambda (x))", "(lambda (a))"),
                 ("(let ())", "(let ())"), ("(letrec ())", "(letrec ())"),
                 ("(lambda (x) x", "(lambda (a) a)"))
        for malformed, other in cases:
            with self.subTest(malformed=malformed):
                self.assertFalse(alpha_equivalent(malformed, other))


if __name__ == "__main__":
    unittest.main()
