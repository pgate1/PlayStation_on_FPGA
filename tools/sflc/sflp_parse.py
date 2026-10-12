#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""SFL+ (.sflp) parser — feasibility spike for a self-made sflp/sfl2vl replacement.

Parses pgate1's SFL+ dialect into a plain tuple/dict AST. No code generation yet.
Binary expressions are kept FLAT (operand, op, operand, ...) because the SFL+
operator precedence is not documented; see analyze_mixed().

Usage: sflp_parse.py [-D NAME]... [--report] files...
"""
import re
import sys
from collections import Counter

# --------------------------------------------------------------------------- preprocess

def preprocess(text, defines):
    """Strip comments, apply #ifdef/#ifndef/#else/#endif/#define and %d macros.
    Returns (lines, includes). Line structure is preserved for error messages."""
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    # comments -> spaces, preserving newlines
    def blank(m):
        return re.sub(r'[^\n]', ' ', m.group())
    text = re.sub(r'/\*.*?\*/|//[^\n]*', blank, text, flags=re.S)
    out, includes, macros = [], [], {}
    stack = []  # (active_parent, this_branch_active)
    active = True
    for line in text.split('\n'):
        s = line.strip()
        m = re.match(r'#(ifdef|ifndef)\s+(\w+)', s)
        if m:
            cond = (m.group(2) in defines) == (m.group(1) == 'ifdef')
            stack.append((active, cond))
            active = active and cond
            out.append('')
            continue
        if s.startswith('#else'):
            parent, cond = stack[-1]
            stack[-1] = (parent, not cond)
            active = parent and not cond
            out.append('')
            continue
        if s.startswith('#endif'):
            active = stack.pop()[0]
            out.append('')
            continue
        if not active:
            out.append('')
            continue
        m = re.match(r'#define\s+(\w+)(?:\s+(.*))?$', s)
        if m:
            defines.add(m.group(1))
            if m.group(2):
                macros[m.group(1)] = m.group(2)
            out.append('')
            continue
        m = re.match(r'%d\s+(\w+)\s+(.*)$', s)
        if m:
            macros[m.group(1)] = m.group(2).strip()
            out.append('')
            continue
        m = re.match(r'%i\s+"([^"]+)"', s)
        if m:
            includes.append(m.group(1))
            out.append('')
            continue
        if s.startswith('#') or s.startswith('%'):
            raise SyntaxError('unknown directive: ' + s)
        if macros:
            line = re.sub(r'\b\w+\b', lambda mm: macros.get(mm.group(), mm.group()), line)
        out.append(line)
    if stack:
        raise SyntaxError('unterminated #ifdef')
    return out, includes, macros

# --------------------------------------------------------------------------- lexer

OPS = [':=', '==', '!=', '||', '&&', '<<', '>>', '++', '--', '+=', '-=', '&=', '|=',
       '^=', '@=', '/|', '/&', '/@', '/^',
       '{', '}', '(', ')', '[', ']', '<', '>', ';', ':', ',', '.', '#', '=', '+', '-',
       '&', '|', '^', '@', '!', '~', '*', '/', '\\', '?']
KEYWORDS = {'declare', 'interface', 'circuit', 'module', 'input', 'output', 'bidirect',
            'inout', 'instrin', 'instrout', 'instrself', 'instr_arg', 'sel', 'sel_v',
            'bus', 'bus_v', 'reg', 'reg_wr', 'reg_ws', 'mem', 'stage_name', 'task',
            'instruct', 'stage', 'state_name', 'first_state', 'state', 'segment',
            'par', 'alt', 'any', 'join', 'if', 'else', 'switch', 'case', 'default', 'goto',
            'generate', 'relay', 'finish', 'call', 'return'}
TOKEN_RE = re.compile(
    r'(?P<ws>[ \t\f\v]+)|(?P<nl>\n)'
    r'|(?P<const>0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+)'
    r'|(?P<num>[0-9]+)'
    r'|(?P<name>[A-Za-z_][A-Za-z0-9_]*)'
    r'|(?P<str>"[^"\n]*")'
    r'|(?P<op>' + '|'.join(re.escape(o) for o in sorted(OPS, key=len, reverse=True)) + ')')


class Tok:
    __slots__ = ('kind', 'val', 'line')

    def __init__(self, kind, val, line):
        self.kind, self.val, self.line = kind, val, line

    def __repr__(self):
        return '%s:%r@%d' % (self.kind, self.val, self.line)


def lex(lines):
    toks = []
    text = '\n'.join(lines)
    pos, line = 0, 1
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m:
            raise SyntaxError('line %d: bad character %r' % (line, text[pos]))
        kind = m.lastgroup
        val = m.group()
        if kind == 'nl':
            line += 1
        elif kind != 'ws':
            if kind == 'name' and val in KEYWORDS:
                kind = 'kw'
            toks.append(Tok(kind, val, line))
        pos = m.end()
    toks.append(Tok('eof', None, line))
    return toks

# --------------------------------------------------------------------------- parser

STATS = Counter()
MIXED = []  # (file, line, ops tuple, source text)


class Parser:
    def __init__(self, toks, fname):
        self.t, self.i, self.f = toks, 0, fname

    # -- helpers
    @property
    def cur(self):
        return self.t[self.i]

    def peek(self, k=1):
        return self.t[min(self.i + k, len(self.t) - 1)]

    def at(self, *vals):
        return self.cur.val in vals and self.cur.kind in ('op', 'kw')

    def eat(self, val=None, kind=None):
        tok = self.cur
        if val is not None and (tok.val != val or tok.kind not in ('op', 'kw')):
            self.err('expected %r' % val)
        if kind is not None and tok.kind != kind:
            self.err('expected %s' % kind)
        self.i += 1
        return tok

    def accept(self, val):
        if self.at(val):
            self.i += 1
            return True
        return False

    def err(self, msg):
        tok = self.cur
        raise SyntaxError('%s:%d: %s, got %s %r' % (self.f, tok.line, msg, tok.kind, tok.val))

    def name(self):
        return self.eat(kind='name').val

    # -- top level
    def file(self):
        items = []
        while self.cur.kind != 'eof':
            if self.at('declare'):
                items.append(self.declare())
            elif self.at('circuit', 'module'):
                items.append(self.circuit())
            else:
                self.err('expected declare/circuit/module')
        return items

    def declare(self):
        self.eat('declare')
        name = self.name()
        iface = self.accept('interface')
        STATS['declare' + (' interface' if iface else '')] += 1
        self.eat('{')
        body = []
        while not self.at('}'):
            body.append(self.decl_item())
        self.eat('}')
        return ('declare', name, iface, body)

    def circuit(self):
        kind = self.eat().val
        name = self.name()
        STATS[kind] += 1
        self.eat('{')
        body = []
        while not self.at('}'):
            body.append(self.circuit_item())
        self.eat('}')
        return (kind, name, body)

    DECL_KW = ('input', 'output', 'bidirect', 'inout', 'instrin', 'instrout', 'instrself',
               'instr_arg', 'sel', 'sel_v', 'bus', 'bus_v', 'reg', 'reg_wr', 'reg_ws', 'mem',
               'stage_name')

    def decl_item(self):
        if not self.at(*self.DECL_KW):
            self.err('expected declaration')
        kw = self.eat().val
        STATS['decl ' + kw] += 1
        if kw == 'stage_name':
            name = self.name()
            self.eat('{')
            tasks = []
            while self.accept('task'):
                tname = self.name()
                self.eat('(')
                args = self.name_list(')')
                self.eat(')')
                self.eat(';')
                tasks.append((tname, args))
            self.eat('}')
            return ('stage_name', name, tasks)
        if kw == 'instr_arg':
            name = self.name()
            if self.accept('.'):
                name += '.' + self.name()
            self.eat('(')
            args = self.name_list(')')
            self.eat(')')
            self.eat(';')
            return ('instr_arg', name, args)
        items = []
        while True:
            n = self.name()
            ent = {'name': n}
            if kw == 'mem':
                self.eat('[')
                ent['depth'] = self.expr()
                self.eat(']')
            if self.at('<'):
                self.eat('<')
                ent['width'] = self.slice_bound()
                self.eat('>')
            if self.at('(') and kw in ('instrin', 'instrout', 'instrself'):
                self.eat('(')
                ent['args'] = self.name_list(')')
                self.eat(')')
                STATS['decl %s(args)' % kw] += 1
            if self.accept('='):
                STATS['decl %s init' % kw] += 1
                if self.at('{'):
                    self.eat('{')
                    vals = []
                    while not self.at('}'):
                        vals.append(self.expr())
                        if not self.accept(','):
                            break
                    self.eat('}')
                    ent['init'] = ('list', vals)
                else:
                    ent['init'] = self.expr()
            items.append(ent)
            if not self.accept(','):
                break
        self.eat(';')
        return ('decl', kw, items)

    def name_list(self, end):
        names = []
        if self.at(end):
            return names
        names.append(self.name())
        while self.accept(','):
            names.append(self.name())
        return names

    def circuit_item(self):
        tok = self.cur
        if self.at(*self.DECL_KW):
            return self.decl_item()
        if self.at('declare'):
            return self.declare()
        if self.at('instruct'):
            self.eat()
            name = self.name()
            if self.accept('.'):
                name += '.' + self.name()
                STATS['instruct sub.x'] += 1
            STATS['instruct'] += 1
            return ('instruct', name, self.action(), tok.line)
        if self.at('stage'):
            return self.stage()
        # submodule instance: TYPE name[, name];
        if tok.kind == 'name' and self.peek().kind == 'name':
            typ = self.name()
            names = []
            while True:
                n = self.name()
                if self.at('['):
                    self.eat('[')
                    n = (n, self.expr())
                    self.eat(']')
                    STATS['submodule array'] += 1
                names.append(n)
                if not self.accept(','):
                    break
            self.eat(';')
            STATS['submodule instance'] += 1
            return ('inst', typ, names)
        return ('always', self.action())

    def stage(self):
        line = self.eat('stage').line
        name = self.name()
        STATS['stage'] += 1
        self.eat('{')
        body = []
        while not self.at('}'):
            if self.at('state_name', 'first_state'):
                kw = self.eat().val
                STATS[kw] += 1
                names = [self.name()]
                while self.accept(','):
                    names.append(self.name())
                self.eat(';')
                body.append((kw, names))
            elif self.at('state'):
                sline = self.eat().line
                sname = self.name()
                STATS['state'] += 1
                body.append(('state', sname, self.action(), sline))
            elif self.at(*self.DECL_KW):
                STATS['decl inside stage'] += 1
                body.append(self.decl_item())
            else:
                body.append(('common', self.action()))
        self.eat('}')
        return ('stage', name, body, line)

    # -- actions
    def gen_header(self):
        """par(i=0;i<N;i++) / alt(...) generator header."""
        self.eat('(')
        var = self.name()
        self.eat('=')
        start = self.expr()
        self.eat(';')
        v2 = self.name()
        if v2 != var:
            self.err('generator variable mismatch')
        cmp = self.eat().val  # '<'
        if cmp != '<':
            self.err('generator expects <')
        end = self.expr_noslice()
        self.eat(';')
        v3 = self.name()
        if v3 != var:
            self.err('generator increment variable mismatch')
        self.eat('++')
        self.eat(')')
        return (var, start, end)

    def action(self):
        tok = self.cur
        line = tok.line
        if self.at(*self.DECL_KW) or self.at('instruct', 'stage') or (
                tok.kind == 'name' and self.peek().kind == 'name'):
            STATS['decl/instance/instruct inside action'] += 1
            return ('item', self.circuit_item())
        if self.at('par', 'alt', 'any', 'join'):
            kw = self.eat().val
            gen = None
            if self.at('('):
                gen = self.gen_header()
                STATS['%s generator' % kw] += 1
            if kw in ('par', 'join'):
                if self.at('{'):
                    self.eat('{')
                    acts = []
                    while not self.at('}'):
                        acts.append(self.action())
                    self.eat('}')
                else:
                    acts = [self.action()]
                STATS[kw] += 1
                return (kw, gen, acts, line)
            self.eat('{')
            arms, els = [], None
            while not self.at('}'):
                if self.at('else'):
                    self.eat()
                    self.eat(':')
                    els = self.action()
                    STATS['%s else' % kw] += 1
                    continue
                g = self.expr()
                self.eat(':')
                arms.append((g, self.action()))
            self.eat('}')
            STATS[kw] += 1
            return (kw, gen, arms, els, line)
        if self.at('if'):
            self.eat()
            self.eat('(')
            c = self.expr()
            self.eat(')')
            a = self.action()
            e = None
            # 'else :' belongs to an enclosing any/alt, not to this if
            if self.at('else') and not (self.peek().kind == 'op' and self.peek().val == ':'):
                self.eat('else')
                e = self.action()
                STATS['if-else'] += 1
            STATS['if'] += 1
            return ('if', c, a, e, line)
        if self.at('switch'):
            self.eat()
            self.eat('(')
            sel = self.expr()
            self.eat(')')
            self.eat('{')
            cases = []
            while not self.at('}'):
                if self.accept('default'):
                    key = None
                    STATS['switch default'] += 1
                else:
                    self.eat('case')
                    key = self.expr()
                self.eat(':')
                acts = []
                while not self.at('case', 'default', '}'):
                    acts.append(self.action())
                if len(acts) > 1:
                    STATS['case with >1 action'] += 1
                cases.append((key, acts))
            self.eat('}')
            STATS['switch'] += 1
            return ('switch', sel, cases, line)
        if self.at('{'):
            self.eat()
            acts = []
            while not self.at('}'):
                acts.append(self.action())
            self.eat('}')
            STATS['bare block'] += 1
            return ('par', None, acts, line)
        if self.accept(';'):
            STATS['nop'] += 1
            return ('nop', line)
        if self.at('goto'):
            self.eat()
            n = self.name()
            self.eat(';')
            STATS['goto'] += 1
            return ('goto', n, line)
        if self.at('finish'):
            self.eat()
            self.eat(';')
            STATS['finish'] += 1
            return ('finish', line)
        if self.at('generate', 'relay'):
            kw = self.eat().val
            st = self.name()
            self.eat('.')
            task = self.name()
            self.eat('(')
            args = self.expr_list(')')
            self.eat(')')
            self.eat(';')
            STATS[kw] += 1
            return (kw, st, task, args, line)
        if self.at('return', 'call'):
            self.err('call/return not supported in spike')
        # assignment or invocation
        if tok.kind != 'name':
            self.err('expected action')
        lhs = self.lvalue()
        if self.at(':=', '='):
            op = self.eat().val
            rhs = self.expr()
            self.eat(';')
            STATS['assign ' + op] += 1
            return ('assign', op, lhs, rhs, line)
        if self.at('++', '--'):
            op = self.eat().val
            self.eat(';')
            STATS['assign ' + op] += 1
            return ('incdec', op, lhs, line)
        if self.at('+=', '-=', '&=', '|=', '^=', '@='):
            op = self.eat().val
            rhs = self.expr()
            self.eat(';')
            STATS['assign ' + op] += 1
            return ('opassign', op, lhs, rhs, line)
        if self.at('('):
            self.eat('(')
            args = self.expr_list(')')
            self.eat(')')
            self.eat(';')
            STATS['invoke'] += 1
            return ('invoke', lhs, args, line)
        self.err('expected := = ++ -- op= or (')

    def lvalue(self):
        n = self.name()
        node = ('name', n)
        while True:
            if self.at('.'):
                self.eat()
                node = ('dot', node, self.name())
            elif self.at('['):
                self.eat()
                idx = self.expr()
                self.eat(']')
                node = ('index', node, idx)
            elif self.at('<') and self.looks_like_slice():
                node = self.slice(node)
                STATS['lvalue slice'] += 1
            else:
                return node

    # -- expressions (flat binary chains)
    BINOPS = ('|', '&', '@', '||', '+', '-', '*', '>>', '<<', '==', '!=', '&&', '^')

    def expr_list(self, end):
        args = []
        if self.at(end):
            return args
        args.append(self.expr())
        while self.accept(','):
            args.append(self.expr())
        return args

    def expr(self):
        line = self.cur.line
        start = self.i
        terms = [self.unary()]
        ops = []
        while self.cur.kind == 'op' and self.cur.val in self.BINOPS:
            ops.append(self.eat().val)
            terms.append(self.unary())
        if len(ops) == 0:
            return terms[0]
        STATS['binop ' + ' '.join(sorted(set(ops)))] += 0  # placeholder keeps key list
        if len(set(ops)) > 1:
            src = ' '.join(str(t.val) for t in self.t[start:self.i])
            MIXED.append((self.f, line, tuple(ops), src))
        return ('chain', terms, ops)

    def expr_noslice(self):
        """Width / generator bounds: a single unary, no top-level '<'/'>' consumption."""
        return self.unary(noslice=True)

    def unary(self, noslice=False):
        tok = self.cur
        if tok.kind == 'op' and tok.val in ('^', '-', '!', '~', '/|', '/&', '/@', '/^', '/', '\\'):
            self.eat()
            STATS['unary ' + tok.val] += 1
            return ('un', tok.val, self.unary(noslice))
        if tok.kind == 'num' and self.peek().kind == 'op' and self.peek().val == '#':
            self.eat()
            self.eat('#')
            STATS['sign-extend N#'] += 1
            return ('sext', int(tok.val), self.unary(noslice))
        return self.postfix(self.primary(), noslice)

    def looks_like_slice(self):
        # '<' expr [':' expr] '>' where exprs are simple (num/name/arith of them)
        j = self.i + 1
        depth = 0
        angle = 0
        while j < len(self.t):
            tk = self.t[j]
            if tk.kind == 'op' and tk.val == '(':
                depth += 1
            elif tk.kind == 'op' and tk.val == ')':
                depth -= 1
            elif depth == 0 and tk.kind == 'op' and tk.val == '<':
                angle += 1
            elif depth == 0 and tk.kind == 'op' and tk.val == '>':
                if angle == 0:
                    return True
                angle -= 1
            elif tk.kind == 'op' and tk.val in (';', '{', '}', '=', ':=', '==') and depth == 0:
                return False
            elif tk.kind == 'eof':
                return False
            j += 1
        return False

    def slice(self, node):
        self.eat('<')
        hi = self.slice_bound()
        lo = None
        if self.accept(':'):
            lo = self.slice_bound()
        self.eat('>')
        STATS['slice'] += 1
        return ('slice', node, hi, lo)

    def slice_bound(self):
        # bounds are constants or generator arithmetic like i*2+1
        terms = [self.bound_unary()]
        ops = []
        while self.cur.kind == 'op' and self.cur.val in ('+', '-', '*'):
            ops.append(self.eat().val)
            terms.append(self.bound_unary())
        return terms[0] if not ops else ('chain', terms, ops)

    def bound_unary(self):
        u = self.unary(noslice=True)
        # nested constant slice inside a bound: io_Din< (i-16)<3:0> >
        t = self.t
        if self.at('<') and t[self.i + 1].kind == 'num' and (
                (t[self.i + 2].val == '>' and t[self.i + 3].val in ('>', ':')) or
                (t[self.i + 2].val == ':' and t[self.i + 3].kind == 'num' and t[self.i + 4].val == '>'
                 and t[self.i + 5].val in ('>', ':'))):
            u = self.slice_fixed(u)
            STATS['nested slice in bound'] += 1
        return u

    def slice_fixed(self, node):
        self.eat('<')
        hi = ('num', self.eat(kind='num').val)
        lo = None
        if self.accept(':'):
            lo = ('num', self.eat(kind='num').val)
        self.eat('>')
        return ('slice', node, hi, lo)

    def postfix(self, node, noslice=False):
        while True:
            if self.at('<') and not noslice and self.looks_like_slice():
                node = self.slice(node)
            elif self.at('['):
                self.eat()
                idx = self.expr()
                self.eat(']')
                node = ('index', node, idx)
                STATS['mem/array index'] += 1
            elif self.at('.'):
                self.eat()
                node = ('dot', node, self.name())
            elif self.at('(') and node[0] in ('name', 'dot'):
                self.eat()
                args = self.expr_list(')')
                self.eat(')')
                node = ('call', node, args)
                STATS['invoke-in-expr'] += 1
            else:
                return node

    def primary(self):
        tok = self.cur
        if tok.kind == 'name':
            self.eat()
            return ('name', tok.val)
        if tok.kind in ('num', 'const'):
            self.eat()
            return (tok.kind, tok.val)
        if tok.kind == 'str':
            self.eat()
            STATS['string constant'] += 1
            return ('str', tok.val)
        if self.at('('):
            self.eat()
            e = self.expr()
            self.eat(')')
            return ('paren', e)
        self.err('expected expression')

# --------------------------------------------------------------------------- driver

def parse_file(path, defines):
    with open(path, 'rb') as source:
        raw = source.read().decode('latin1')
    lines, includes, macros = preprocess(raw, set(defines))
    toks = lex(lines)
    ast = Parser(toks, path).file()
    return ast, includes


def main(argv):
    defines, files, report = [], [], False
    it = iter(argv)
    for a in it:
        if a == '-D':
            defines.append(next(it))
        elif a == '--report':
            report = True
        else:
            files.append(a)
    ok = fail = 0
    total_lines = 0
    for f in files:
        try:
            parse_file(f, defines)
            ok += 1
            with open(f, 'rb') as source:
                total_lines += source.read().count(b'\n')
        except SyntaxError as e:
            fail += 1
            print('FAIL', e)
    print('parsed %d/%d files (%d lines)' % (ok, ok + fail, total_lines))
    if report:
        print('\nconstruct counts:')
        for k, v in sorted(STATS.items()):
            if v:
                print('  %-28s %d' % (k, v))
        pairs = Counter(tuple(sorted(set(m[2]))) for m in MIXED)
        print('\nunparenthesized mixed-operator chains: %d' % len(MIXED))
        for k, v in pairs.most_common():
            print('  %-30s %d' % (' '.join(k), v))
    return 1 if fail else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
