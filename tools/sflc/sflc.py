#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Experimental SFL+ -> SystemVerilog compiler for isolated block validation.

Supports guarded combinational logic, registers, one-port memories, local
control terminals/arguments, lexical locals, stages and interface linking.
Not a qualified full-core compiler. See docs/POCKET_SFLC.md for semantic limits.
Unsupported constructs fail rather than silently disappear.

Usage: sflc.py [-D NAME]... [--assertions] file.sflp > out.sv
"""
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sflp_parse  # noqa: E402

BIN = {'|': '|', '&': '&', '@': '^', '+': '+', '-': '-', '*': '*',
       '==': '==', '!=': '!=', '<<': '<<', '>>': '>>'}
UN = {'^': '~', '~': '~', '!': '!', '-': '-', '/|': '|', '/&': '&',
      '/@': '^', '/^': '^'}
REGS = ('reg', 'reg_wr', 'reg_ws')


def constant(n):
    """Evaluate declaration bounds; runtime expressions are not bounds."""
    k = n[0]
    if k == 'num':
        return int(n[1])
    if k == 'const':
        return int(n[1].replace('_', ''), 0)
    if k == 'paren':
        return constant(n[1])
    if k == 'un' and n[1] == '-':
        return -constant(n[2])
    if k == 'chain':
        v = constant(n[1][0])
        for op, rhs in zip(n[2], n[1][1:]):
            r = constant(rhs)
            if op == '+': v += r
            elif op == '-': v -= r
            elif op == '*': v *= r
            else: raise NotImplementedError('constant operator ' + op)
        return v
    raise NotImplementedError('nonconstant declaration/bound: ' + repr(n))


def const_text(kind, val):
    if kind == 'num':
        return val
    base = {'x': 'h', 'b': 'b', 'o': 'o'}[val[1].lower()]
    digits = val[2:].replace('_', '')
    width = len(digits) * {'b': 1, 'o': 3, 'h': 4}[base]
    return "%d'%s%s" % (width, base, digits)


class Scope:
    """Hoist declarations after alpha-renaming each lexical block.

    Declarations are visible throughout their containing block (SFL+ accepts
    declaration after use). Sibling block locals never share a register/wire.
    """
    def __init__(self):
        self.declarations = []
        self.interfaces = []
        self.serial = 0

    def expr(self, n, env):
        if not isinstance(n, tuple):
            return n
        if n[0] == 'name':
            if n[1] not in env:
                raise NameError('undeclared ' + n[1])
            return ('name', env[n[1]])
        if n[0] == 'dot':
            member = n[2]
            # Local instruction calls return a named signal in the same scope.
            if n[1][0] == 'call' and n[1][1][0] == 'name':
                if member not in env: raise NameError('undeclared call result ' + member)
                member = env[member]
            return ('dot', self.expr(n[1], env), member)
        return tuple(self.expr(x, env) if isinstance(x, tuple) else
                     [self.expr(y, env) for y in x] if isinstance(x, list) else x
                     for x in n)

    @staticmethod
    def declaration(item):
        # The parser wraps stage-level instance declarations in common/item;
        # that syntax does not introduce a new lexical block.
        if item[0] in ('common', 'always') and item[1][0] == 'item':
            return item[1][1]
        return item[1] if item[0] == 'item' else item

    def block(self, items, outer, root=False):
        env = dict(outer)
        local = set()
        for item in items:
            d = self.declaration(item)
            names = ([e['name'] for e in d[2]] if d[0] == 'decl' else
                     [d[1]] if d[0] == 'stage_name' else
                     d[2] if d[0] == 'inst' else [])
            for name in names:
                if not isinstance(name, str): raise NotImplementedError('instance arrays')
                if name in local or name in ('p_reset', 'm_clock') or name.startswith('__sfl_'):
                    raise ValueError('duplicate/reserved declaration ' + name)
                local.add(name)
                self.serial += 1
                env[name] = name if root else '__sfl_local_%d_%s' % (self.serial, name)
        out = []
        for item in items:
            d = self.declaration(item)
            if d[0] == 'decl':
                entries = []
                for e in d[2]:
                    ent = dict(e, name=env[e['name']])
                    for key in ('width', 'depth', 'init'):
                        if key in ent: ent[key] = self.expr(ent[key], env)
                    if 'args' in ent: ent['args'] = [env[a] for a in ent['args']]
                    entries.append(ent)
                self.declarations.append(('decl', d[1], entries))
            elif d[0] == 'stage_name':
                if not root:
                    raise NotImplementedError('nested stage declaration')
                self.declarations.append(('stage_name', env[d[1]],
                                          [(t, [env[a] for a in args]) for t, args in d[2]]))
            elif d[0] == 'instr_arg':
                self.declarations.append(('instr_arg', env[d[1]], [env[a] for a in d[2]]))
            elif d[0] == 'inst':
                self.declarations.append(('inst', d[1], [env[n] for n in d[2]]))
            elif d[0] == 'declare':
                self.interfaces.append(d)
            else:
                out.append(self.action(item, env))
        return out

    def action(self, a, env):
        k = a[0]
        if k in ('par', 'join'):
            if a[1] is not None or k == 'join':
                raise NotImplementedError(k + ' generator')
            return ('par', None, self.block(a[2], env), a[-1])
        if k in ('any', 'alt'):
            if a[1] is not None: raise NotImplementedError(k + ' generator')
            return (k, None, [(self.expr(g, env), self.action(b, env)) for g, b in a[2]],
                    None if a[3] is None else self.action(a[3], env), a[-1])
        if k == 'if':
            return (k, self.expr(a[1], env), self.action(a[2], env),
                    None if a[3] is None else self.action(a[3], env), a[-1])
        if k == 'switch':
            return (k, self.expr(a[1], env),
                    [(None if key is None else self.expr(key, env), self.block(body, env))
                     for key, body in a[2]], a[-1])
        if k in ('always', 'common'):
            return (k, self.action(a[1], env))
        if k == 'instruct':
            parts = a[1].split('.')
            if parts[0] not in env: raise NameError('undeclared instruction ' + a[1])
            name = '.'.join([env[parts[0]], *parts[1:]])
            return (k, name, self.action(a[2], env), a[-1])
        if k == 'stage':
            if a[1] not in env: raise NameError('undeclared stage ' + a[1])
            return (k, env[a[1]], self.block(a[2], env), a[-1])
        if k == 'state':
            return (k, a[1], self.action(a[2], env), a[-1])
        if k in ('state_name', 'first_state', 'goto', 'finish', 'nop'):
            return a
        if k in ('generate', 'relay'):
            if a[1] not in env: raise NameError('undeclared stage ' + a[1])
            return (k, env[a[1]], a[2], [self.expr(x, env) for x in a[3]], a[-1])
        if k == 'item':
            # A single declaration/instruct used as a branch's entire action.
            return ('par', None, self.block([a[1]], env), 0)
        if k in ('decl', 'inst', 'declare', 'stage_name', 'instr_arg'):
            raise NotImplementedError('circuit item ' + k)
        return self.expr(a, env)


class Gen:
    def __init__(self, name, assertions=False, interfaces=None):
        self.name = name
        self.assertions = assertions
        self.ports = []
        self.decls = {}       # name -> bit count (always numeric)
        self.kinds = {}
        self.resets = {}      # registers with asynchronous reset values
        self.memories = {}    # name -> (depth, initial values or None)
        self.instructions = {}  # terminal -> formal signal names
        self.stages = {}
        self.drivers = {}     # target -> [(guards, expression)]
        self.writes = {}      # memory -> [(guards, address, expression)]
        self.temps = []
        self.interfaces = dict(interfaces or {})
        self.instances = {}   # instance name -> (Interface, port alias mapping)
        self.observed_controls = set()
        self.expression_guards = []

    def port_ref(self, instance, member):
        if instance not in self.instances: raise NameError('unknown instance ' + instance)
        ports = self.instances[instance][1]
        if member not in ports: raise NameError('unknown port %s.%s' % (instance, member))
        return ports[member]

    def call_target(self, target):
        if target[0] == 'name': return target[1]
        if target[0] == 'dot' and target[1][0] == 'name':
            return self.port_ref(target[1][1], target[2])
        raise NotImplementedError('nested invocation target')

    def call_result(self, call, member):
        target = call[1]
        if target[0] == 'name':
            self.width_name(member)
            return member
        if target[0] == 'dot' and target[1][0] == 'name':
            return self.port_ref(target[1][1], member)
        raise NotImplementedError('nested call result')

    def instantiate(self, item):
        if item[1] not in self.interfaces: raise NameError('undeclared module type ' + item[1])
        interface = self.interfaces[item[1]]
        for instance in item[2]:
            aliases = {}
            for member, (kind, width) in interface.ports.items():
                alias = '__sfl_port_%d_%s' % (len(self.instances), member)
                aliases[member] = alias
                parent_kind = {'input': 'sel', 'instrin': 'instrself',
                               'output': 'external', 'instrout': 'external'}[kind]
                self.add_decl(alias, parent_kind, width)
                if kind == 'instrout': self.observed_controls.add(alias)
            for member, (kind, _) in interface.ports.items():
                if kind == 'instrin':
                    self.instructions[aliases[member]] = [aliases[n] for n in interface.arguments.get(member, [])]
            self.instances[instance] = (interface, aliases)

    def temp(self, expr, width):
        name = '__sfl_expr_%d' % len(self.temps)
        self.temps.append((name, width, expr))
        return name

    def width_name(self, name):
        if name not in self.decls: raise NameError('undeclared ' + name)
        return self.decls[name]

    def width(self, n):
        k = n[0]
        if k == 'name': return self.width_name(n[1])
        if k == 'num': return max(1, int(n[1]).bit_length())
        if k == 'const': return len(n[1][2:].replace('_', '')) * {'x': 4, 'b': 1, 'o': 3}[n[1][1].lower()]
        if k == 'paren': return self.width(n[1])
        if k == 'sext': return n[1]
        if k == 'slice':
            return 1 if n[3] is None else abs(constant(n[2]) - constant(n[3])) + 1
        if k == 'index': return self.width(n[1])
        if k == 'dot':
            if n[1][0] == 'call': return self.width_name(self.call_result(n[1], n[2]))
            if n[1][0] == 'name' and n[1][1] in self.instances:
                return self.width_name(self.port_ref(n[1][1], n[2]))
            self.stage_ref(n)
            return 1
        if k == 'un': return 1 if n[1] in ('/|', '/&', '/@', '/^', '!') else self.width(n[2])
        if k == 'chain':
            w = self.width(n[1][0])
            for op, t in zip(n[2], n[1][1:]):
                if op == '||': w += self.width(t)
                elif op in ('==', '!='): w = 1
                elif op not in ('<<', '>>'): w = max(w, self.width(t))
            return w
        raise NotImplementedError('expression width ' + k)

    def stage_ref(self, n):
        if n[1][0] != 'name' or n[1][1] not in self.stages:
            raise NotImplementedError('submodule expression')
        st = self.stages[n[1][1]]
        if n[2] not in st['tasks']: raise NameError('unknown stage task ' + n[2])
        return st['tasks'][n[2]]

    def expr(self, n, context=None):
        k = n[0]
        if k == 'name':
            self.width_name(n[1])
            if self.kinds[n[1]] == 'mem': raise ValueError('memory requires index')
            return n[1]
        if k == 'num':
            # Decimal SFL literals inherit the enclosing data width. Size them
            # explicitly so Verilog cannot sign-extend or widen a concatenation.
            return "%d'd%s" % (context or self.width(n), n[1])
        if k == 'const': return const_text(k, n[1])
        if k == 'paren': return '(' + self.expr(n[1], context) + ')'
        if k == 'dot':
            if n[1][0] == 'call':
                result = self.call_result(n[1], n[2])
                self.invoke(n[1][1], n[1][2], self.expression_guards)
                return result
            if n[1][0] == 'name' and n[1][1] in self.instances:
                return self.port_ref(n[1][1], n[2])
            return self.stage_ref(n)['active']
        if k == 'index':
            if n[1][0] != 'name' or n[1][1] not in self.memories:
                raise NotImplementedError('index of non-memory')
            return '%s[%s]' % (n[1][1], self.expr(n[2]))
        if k == 'chain':
            # Build a binary tree with SFL's left-to-right rule, then let the
            # surrounding operation determine decimal-literal sizing.
            tree = n[1][0]
            for op, t in zip(n[2], n[1][1:]): tree = ('binary', op, tree, t)
            return self.binary(tree, context)
        if k == 'un':
            if n[1] not in UN: raise NotImplementedError('unary ' + n[1])
            return '%s(%s)' % (UN[n[1]], self.expr(n[2], context))
        if k == 'slice':
            hi = constant(n[2]); lo = hi if n[3] is None else constant(n[3])
            w = self.width(n[1])
            if min(hi, lo) < 0 or max(hi, lo) >= w:
                raise ValueError('slice outside expression width: ' + repr(n))
            base = self.expr(n[1])
            if n[1][0] != 'name': base = self.temp(base, w)
            if hi < lo: return '{' + ','.join('%s[%d]' % (base, b) for b in range(hi, lo + 1)) + '}'
            if hi == lo: return base if w == 1 else '%s[%d]' % (base, hi)
            return '%s[%d:%d]' % (base, hi, lo)
        if k == 'sext':
            total, src = n[1], n[2]
            w = self.width(src)
            if total < w: raise ValueError('sign extension cannot narrow')
            base = self.expr(src)
            if total == w: return base
            # Arbitrary expressions use a sized temporary so the sign bit is
            # taken before extension, independent of destination context.
            tmp = base if src[0] == 'name' else self.temp(base, w)
            sign = tmp if w == 1 else '%s[%d]' % (tmp, w - 1)
            return '{{%d{%s}},%s}' % (total - w, sign, tmp)
        raise NotImplementedError('expression ' + k)

    def binary_width(self, n):
        if n[0] != 'binary': return self.width(n)
        _, op, a, b = n
        wa, wb = self.binary_width(a), self.binary_width(b)
        if op == '||': return wa + wb
        if op in ('==', '!='): return 1
        if op in ('<<', '>>'): return wa
        return max(wa, wb)

    def binary(self, n, context):
        if n[0] != 'binary': return self.expr(n, context)
        _, op, a, b = n
        wa, wb = self.binary_width(a), self.binary_width(b)
        if op == '||': return '{%s,%s}' % (self.binary(a, None), self.binary(b, None))
        if op not in BIN: raise NotImplementedError('binary operator ' + op)
        if op in ('==', '!='): ctx = max(wa, wb)
        elif op in ('<<', '>>'): ctx = max(wa, context or 0)
        else: ctx = max(wa, wb, context or 0)
        return '((%s)%s(%s))' % (self.binary(a, ctx), BIN[op],
                                 self.binary(b, None if op in ('<<', '>>') else ctx))

    def add_decl(self, name, kind, width):
        if name in self.decls: raise ValueError('duplicate declaration ' + name)
        if width < 1: raise ValueError('nonpositive width ' + name)
        self.decls[name], self.kinds[name] = width, kind

    def declare(self, item):
        kw = item[1]
        for ent in item[2]:
            n = ent['name']
            w = constant(ent['width']) if 'width' in ent else 1
            if kw not in ('input', 'output', 'sel', 'instrin', 'instrout', 'instrself', 'mem') + REGS:
                raise NotImplementedError('declaration ' + kw)
            if kw.startswith('instr') and w != 1: raise ValueError('control width must be one')
            self.add_decl(n, kw, w)
            if kw in ('input', 'output', 'instrin', 'instrout'):
                self.ports.append(('input' if kw in ('input', 'instrin') else 'output', n, w))
            if kw.startswith('instr'): self.instructions[n] = ent.get('args', [])
            if kw == 'reg_wr': self.resets[n] = "'0"
            if kw == 'reg_ws': self.resets[n] = "%d'd1" % w
            if 'depth' in ent:
                depth = constant(ent['depth'])
                if depth < 1: raise ValueError('nonpositive memory depth')
                vals = ent.get('init')
                if vals is not None:
                    if vals[0] != 'list': raise ValueError('memory initialization requires list')
                    vals = [constant(value) & ((1 << w) - 1) for value in vals[1]]
                    if len(vals) > depth: raise ValueError('too many memory initializers')
                self.memories[n] = (depth, vals)
            elif 'init' in ent:
                if kw != 'reg': raise NotImplementedError('initializer on ' + kw)
                self.resets[n] = "%d'd%d" % (w, constant(ent['init']) & ((1 << w) - 1))

    def drive(self, target, guards, value, sequential=False):
        if target not in self.kinds: raise NameError('undeclared target ' + target)
        expected = REGS if sequential else ('sel', 'output', 'instrout', 'instrself')
        if self.kinds[target] not in expected:
            raise ValueError('wrong assignment kind for ' + target)
        self.drivers.setdefault(target, []).append((list(guards), value))

    def assign(self, lhs, rhs, guards, sequential):
        if lhs[0] == 'dot' and lhs[1][0] == 'name':
            lhs = ('name', self.port_ref(lhs[1][1], lhs[2]))
        if lhs[0] == 'index' and sequential:
            if lhs[1][0] != 'name' or lhs[1][1] not in self.memories:
                raise ValueError('write target is not a memory')
            name = lhs[1][1]
            self.writes.setdefault(name, []).append((list(guards), self.expr(lhs[2]),
                                                     self.expr(rhs, self.decls[name])))
        elif lhs[0] == 'name':
            self.drive(lhs[1], guards, self.expr(rhs, self.width_name(lhs[1])), sequential)
        else:
            raise NotImplementedError('indexed/sliced assignment target')

    def invoke(self, target, actuals, guards):
        name = self.call_target(target)
        if name not in self.instructions or self.kinds[name] == 'instrin':
            raise ValueError('cannot invoke ' + name)
        args = self.instructions[name]
        if len(args) != len(actuals): raise ValueError('argument count for ' + name)
        self.drive(name, guards, "1'b1")
        for formal, actual in zip(args, actuals):
            self.drive(formal, guards, self.expr(actual, self.decls[formal]))

    def action(self, a, guards, stage=None):
        previous = self.expression_guards
        self.expression_guards = guards
        try:
            self._action(a, guards, stage)
        finally:
            self.expression_guards = previous

    def _action(self, a, guards, stage=None):
        k = a[0]
        if k == 'assign':
            self.assign(a[2], a[3], guards, a[1] == ':=')
        elif k in ('incdec', 'opassign'):
            op = ('+' if a[1] == '++' else '-') if k == 'incdec' else a[1][0]
            rhs = ('num', '1') if k == 'incdec' else a[3]
            self.assign(a[2], ('chain', [a[2], rhs], [op]), guards, True)
        elif k in ('always', 'common'):
            self.action(a[1], guards, stage)
        elif k == 'instruct':
            name = a[1]
            if '.' in name: name = self.port_ref(*name.split('.'))
            if name not in self.instructions and name not in self.observed_controls:
                raise ValueError('instruct requires control terminal')
            self.action(a[2], guards + [name], stage)
        elif k == 'invoke':
            self.invoke(a[1], a[2], guards)
        elif k == 'if':
            c = self.expr(a[1])
            self.action(a[2], guards + [c], stage)
            if a[3] is not None: self.action(a[3], guards + ['!(%s)' % c], stage)
        elif k in ('any', 'alt'):
            seen = []
            for cond, body in a[2]:
                c = self.expr(cond)
                prior = ['!(%s)' % x for x in seen] if k == 'alt' else []
                self.action(body, guards + prior + [c], stage)
                seen.append(c)
            if a[3] is not None:
                self.action(a[3], guards + ['!(%s)' % x for x in seen], stage)
        elif k == 'switch':
            keys = [constant(key) for key, _ in a[2] if key is not None]
            if len(set(keys)) != len(keys) or sum(key is None for key, _ in a[2]) > 1:
                raise ValueError('duplicate switch case/default')
            width = self.width(a[1])
            if any(key < 0 or key >= 1 << width for key in keys):
                raise ValueError('switch case does not fit selector')
            sel = self.expr(a[1]); matches = ['(%s == %d\'d%d)' % (sel, width, key) for key in keys]
            for key, body in a[2]:
                branch = ['!(%s)' % m for m in matches] if key is None else [
                    '(%s == %d\'d%d)' % (sel, width, constant(key))]
                for x in body: self.action(x, guards + branch, stage)
        elif k == 'par':
            for x in a[2]: self.action(x, guards, stage)
        elif k == 'generate':
            st = self.stages[a[1]]
            task = st['tasks'].get(a[2])
            if task is None or len(a[3]) != len(task['args']):
                raise ValueError('stage task/argument mismatch')
            st['start'].append(list(guards))
            task['start'].append(list(guards))
            for formal, actual in zip(task['args'], a[3]):
                self.drive(formal, guards, self.expr(actual, self.decls[formal]), True)
        elif k in ('goto', 'finish'):
            if stage is None: raise ValueError(k + ' outside stage')
            if k == 'finish': stage['stop'].append(list(guards))
            else:
                if a[1] not in stage['states']: raise NameError('unknown state ' + a[1])
                value = "%d'd%d" % (self.decls[stage['state']], stage['states'].index(a[1]))
                self.drive(stage['state'], guards, value, True)
        elif k == 'stage':
            st = self.stages[a[1]]
            for item in a[2]:
                if item[0] in ('state_name', 'first_state'): continue
                if item[0] == 'state':
                    g = '%s == %d' % (st['state'], st['states'].index(item[1]))
                    self.action(item[2], guards + [st['active'], g], st)
                else: self.action(item, guards + [st['active']], st)
        elif k == 'nop': pass
        else: raise NotImplementedError('statement ' + k)

    def run(self, circuit):
        scope = Scope()
        body = scope.block(circuit[2], {}, root=True)
        for item in scope.declarations:
            if item[0] == 'decl': self.declare(item)
        for declaration in scope.interfaces:
            interface = Interface(declaration)
            if interface.name in self.interfaces:
                self.interfaces[interface.name].check_same(interface)
            else: self.interfaces[interface.name] = interface
        for item in scope.declarations:
            if item[0] == 'inst': self.instantiate(item)
        for item in scope.declarations:
            if item[0] == 'instr_arg':
                if item[1] not in self.instructions: raise ValueError('instr_arg without instruction')
                self.instructions[item[1]] = item[2]
            elif item[0] == 'stage_name':
                name = item[1]
                if not item[2]: raise ValueError('stage needs a task')
                active = '__sfl_active_' + name
                self.add_decl(active, 'reg_wr', 1); self.resets[active] = "1'b0"
                tasks = {}
                for task, args in item[2]:
                    if task in tasks: raise ValueError('duplicate stage task ' + task)
                    for arg in args:
                        if self.kinds.get(arg) not in REGS: raise ValueError('stage argument must be a register')
                    task_active = active
                    if len(item[2]) > 1:
                        task_active = '__sfl_task_%s_%s' % (name, task)
                        self.add_decl(task_active, 'reg_wr', 1)
                        self.resets[task_active] = "1'b0"
                    tasks[task] = dict(args=args, active=task_active, start=[])
                self.stages[name] = dict(tasks=tasks, active=active,
                                         states=[], start=[], stop=[], body=False)
        for name, args in self.instructions.items():
            allowed = ('input',) if self.kinds[name] == 'instrin' else ('sel', 'output')
            for arg in args:
                if self.kinds.get(arg) not in allowed: raise ValueError('invalid argument signal for ' + name)
        for item in body:
            if item[0] != 'stage': continue
            st = self.stages[item[1]]
            if st['body']: raise ValueError('duplicate stage body')
            st['body'] = True
            states = [x[1] for x in item[2] if x[0] == 'state']
            if len(set(states)) != len(states): raise ValueError('duplicate state')
            st['states'] = states
            declared = [s for x in item[2] if x[0] == 'state_name' for s in x[1]]
            if declared and set(declared) != set(states): raise ValueError('state_name/body mismatch')
            first = [s for x in item[2] if x[0] == 'first_state' for s in x[1]]
            if states:
                if len(first) != 1 or first[0] not in states: raise ValueError('stage needs one valid first_state')
                state = '__sfl_state_' + item[1]
                self.add_decl(state, 'reg', max(1, (len(states) - 1).bit_length()))
                self.resets[state] = str(states.index(first[0])); st['state'] = state
            elif first: raise ValueError('first_state without state body')
        for st in self.stages.values():
            if not st['body']: raise ValueError('stage declaration without body')
        for item in body: self.action(item, [])
        return self.emit()

    @staticmethod
    def guard(guards):
        return ' && '.join('(%s)' % x for x in guards) or "1'b1"

    def mux(self, terms):
        return ' | '.join('((%s) ? (%s) : \'0)' % (self.guard(gs), val)
                          for gs, val in terms) or "'0"

    def data_mux(self, terms, width):
        # Native -O2 data selectors omit selection for a single distinct value
        # or an unconditional writer. This applies to ordinary data as well as
        # instruction arguments; control terminals retain activation guards.
        values = list(dict.fromkeys(value for _, value in terms))
        # A one-bit literal assignment is a Boolean control equation in the
        # native compiler (p26), unlike a one-bit data signal connection.
        if width == 1 and all(re.fullmatch(r"\d+'[bdho][0-9a-fA-F]+", value.strip('()'))
                              for value in values):
            return self.mux(terms)
        if len(values) == 1 or any(not guards for guards, _ in terms):
            return ' | '.join('(%s)' % value for value in values)
        return self.mux(terms)

    def conflict_checks(self, terms, label):
        if not self.assertions: return []
        lines = []
        for i, (ga, _) in enumerate(terms):
            for gb, _ in terms[i+1:]:
                lines.append('    if ((%s) && (%s)) $fatal(1, "conflicting drivers: %s");' %
                             (self.guard(ga), self.guard(gb), label))
        return lines

    def emit(self):
        def rng(w): return '[%d:0] ' % (w - 1) if w > 1 else ''
        L = ['// Experimental sflc output; see docs/POCKET_SFLC.md.',
             'module %s (%s);' % (self.name, ', '.join(['p_reset', 'm_clock'] + [p[1] for p in self.ports])),
             '  input p_reset, m_clock;']
        port_names = {p[1] for p in self.ports}
        for d, n, w in self.ports: L.append('  %s %s%s;' % (d, rng(w), n))
        for n, w in self.decls.items():
            if n in port_names: continue
            kind = self.kinds[n]
            dims = ' [0:%d]' % (self.memories[n][0] - 1) if kind == 'mem' else ''
            L.append('  %s %s%s%s;' % ('reg' if kind in REGS + ('mem',) else 'wire', rng(w), n, dims))
        for n, w, expr in self.temps:
            L.append('  wire %s%s = %s;' % (rng(w), n, expr))
        for instance, (interface, aliases) in self.instances.items():
            connections = [] if interface.external else ['.p_reset(p_reset)', '.m_clock(m_clock)']
            connections += ['.%s(%s)' % (member, alias) for member, alias in aliases.items()]
            L.append('  %s %s (%s);' % (interface.name, instance, ', '.join(connections)))
        for n, kind in self.kinds.items():
            if kind in ('sel', 'output', 'instrself', 'instrout'):
                terms = self.drivers.get(n, [])
                value = self.data_mux(terms, self.decls[n]) if kind in ('sel', 'output') else self.mux(terms)
                L.append('  assign %s = %s;' % (n, value))
        stage_registers = {st['active'] for st in self.stages.values()}
        stage_registers.update(task['active'] for st in self.stages.values()
                               for task in st['tasks'].values())
        for n, kind in self.kinds.items():
            if kind not in REGS: continue
            if n in stage_registers: continue
            terms = self.drivers.get(n, [])
            reset = self.resets.get(n)
            if not terms and reset is None: continue
            events = 'posedge m_clock' + (' or posedge p_reset' if reset is not None else '')
            L.append('  always @(%s) begin' % events)
            if reset is not None: L.append('    if (p_reset) %s <= %s;' % (n, reset))
            if terms:
                enable = ' || '.join('(%s)' % self.guard(g) for g, _ in terms)
                L.append('    %sif (%s) %s <= %s;' % ('else ' if reset is not None else '', enable, n, self.mux(terms)))
            L.append('  end')
        for name, (depth, vals) in self.memories.items():
            if vals is not None:
                L.append('  initial begin')
                L.append("    for (integer i = 0; i < %d; i = i + 1) %s[i] = '0;" % (depth, name))
                for i, val in enumerate(vals):
                    L.append("    %s[%d] = %d'd%d;" % (name, i, self.decls[name], val))
                L.append('  end')
            writes = self.writes.get(name, [])
            # A single physical write port: select the address and data under
            # the same guards. Assert multiple writers instead of inventing
            # source-order priority or inferring accidental multiport RAM.
            if writes:
                addr = [(g, a) for g, a, _ in writes]; data = [(g, v) for g, _, v in writes]
                enable = ' || '.join('(%s)' % self.guard(g) for g, _, _ in writes)
                L.append('  always @(posedge m_clock) if (%s) %s[%s] <= %s;' %
                         (enable, name, self.mux(addr), self.mux(data)))
        for st in self.stages.values():
            stop = ' || '.join('(%s)' % self.guard(g) for g in st['stop']) or "1'b0"
            # Tasks latch independently. A generate does not cancel other tasks;
            # finish clears all except tasks generated on that same edge.
            bits = [st] + [task for task in st['tasks'].values()
                           if task['active'] != st['active']]
            for bit in bits:
                start = ' || '.join('(%s)' % self.guard(g) for g in bit['start']) or "1'b0"
                L += ['  always @(posedge m_clock or posedge p_reset) begin',
                      "    if (p_reset) %s <= 1'b0;" % bit['active'],
                      "    else %s <= (%s) || (%s && !(%s));" % (bit['active'], start, bit['active'], stop), '  end']
        if self.assertions:
            checks = []
            for n, terms in self.drivers.items():
                if self.kinds[n] not in ('instrout', 'instrself'):
                    checks += self.conflict_checks(terms, n)
            for n, writes in self.writes.items(): checks += self.conflict_checks([(g, v) for g, _, v in writes], n)
            if checks: L += ['  // synthesis translate_off', '  always @(posedge m_clock) if (!p_reset) begin'] + checks + ['  end', '  // synthesis translate_on']
        return '\n'.join(L + ['endmodule', ''])


class Interface:
    """Declared leaf ports, shared by calls, wiring and source-header recovery."""
    def __init__(self, declaration, source=None):
        _, self.name, self.external, body = declaration
        self.source = source
        self.ports = {}
        self.arguments = {}
        for item in body:
            if item[0] == 'instr_arg':
                if item[1] in self.arguments: raise ValueError('duplicate instruction arguments')
                self.arguments[item[1]] = item[2]
                continue
            if item[0] != 'decl': raise NotImplementedError('interface item ' + item[0])
            kind = item[1]
            if kind not in ('input', 'output', 'instrin', 'instrout'):
                raise NotImplementedError('interface direction ' + kind)
            for entry in item[2]:
                name = entry['name']
                if name in self.ports: raise ValueError('duplicate interface port ' + name)
                width = constant(entry['width']) if 'width' in entry else 1
                if width < 1 or (kind.startswith('instr') and width != 1):
                    raise ValueError('invalid interface width ' + name)
                if not self.external and name in ('p_reset', 'm_clock'):
                    raise ValueError('implicit clock/reset already declared')
                if 'depth' in entry or 'init' in entry:
                    raise ValueError('initialized/array interface port ' + name)
                self.ports[name] = (kind, width)
                if 'args' in entry:
                    if name in self.arguments: raise ValueError('duplicate instruction arguments')
                    self.arguments[name] = entry['args']
        for name, args in self.arguments.items():
            if name not in self.ports or self.ports[name][0] not in ('instrin', 'instrout'):
                raise ValueError('arguments on non-control interface port ' + name)
            direction = 'input' if self.ports[name][0] == 'instrin' else 'output'
            for arg in args:
                if arg not in self.ports or self.ports[arg][0] != direction:
                    raise ValueError('invalid interface argument ' + arg)

    def check_same(self, other):
        if (self.external, self.ports, self.arguments) != (other.external, other.ports, other.arguments):
            raise ValueError('conflicting declarations for module ' + self.name)

    @classmethod
    def from_circuit(cls, circuit, source):
        ports = [item for item in circuit[2] if item[0] == 'decl' and
                 item[1] in ('input', 'output', 'instrin', 'instrout')]
        names = {entry['name'] for item in ports for entry in item[2]}
        ports += [item for item in circuit[2] if item[0] == 'instr_arg' and item[1] in names]
        return cls(('declare', circuit[1], False, ports), source)


class Library:
    """Read explicit headers or derive missing generated headers from source.

    A missing foo.h is recoverable ONLY from the exact sibling foo.sflp. No
    recursive file search, guessed replacement interfaces or generated files
    are used. Deriving a header does not imply the implementation compiles.
    """
    def __init__(self, defines=()):
        self.defines = defines
        self.interfaces = {}
        self.headers = set()
        self.stack = []
        self.modules = {}

    def add(self, interface):
        old = self.interfaces.get(interface.name)
        if old is not None:
            old.check_same(interface)
            if old.source is None: old.source = interface.source
        else: self.interfaces[interface.name] = interface

    def header(self, path):
        path = path.resolve()
        if path in self.stack: raise ValueError('cyclic header include: ' + str(path))
        if path in self.headers: return
        if not path.exists():
            source = path.with_suffix('.sflp')
            if path.suffix != '.h' or not source.is_file():
                raise FileNotFoundError('missing interface %s (no matching .sflp source)' % path)
            ast, _ = sflp_parse.parse_file(source, self.defines)
            circuits = [x for x in ast if x[0] in ('circuit', 'module')]
            if len(circuits) != 1 or circuits[0][1] != path.stem:
                raise ValueError('source/header module name mismatch: ' + str(source))
            self.add(Interface.from_circuit(circuits[0], source))
        else:
            ast, includes = sflp_parse.parse_file(path, self.defines)
            self.stack.append(path)
            try:
                for include in includes: self.header(path.parent / include)
                for item in ast:
                    if item[0] != 'declare': raise ValueError('header contains non-interface item')
                    source = path.with_suffix('.sflp')
                    self.add(Interface(item, source if source.is_file() else None))
            finally: self.stack.pop()
        self.headers.add(path)

    def module(self, path):
        path = Path(path).resolve()
        if path in self.modules: return self.modules[path]
        ast, includes = sflp_parse.parse_file(path, self.defines)
        for include in includes: self.header(path.parent / include)
        for item in ast:
            if item[0] == 'declare': self.add(Interface(item))
        circuits = [c for c in ast if c[0] in ('circuit', 'module')]
        if len(circuits) != 1: raise NotImplementedError('expected exactly one circuit')
        circuit = circuits[0]
        self.add(Interface.from_circuit(circuit, path))
        self.modules[path] = circuit
        return circuit


def translate(path, defines=(), assertions=False, hierarchy=False):
    library = Library(defines)
    active, emitted = set(), set()
    results = []

    def visit(source):
        circuit = library.module(source)
        name = circuit[1]
        if name in active: raise ValueError('recursive module instantiation: ' + name)
        if name in emitted: return
        active.add(name)
        generator = Gen(name, assertions, library.interfaces)
        output = generator.run(circuit)
        if hierarchy:
            for interface, _ in generator.instances.values():
                if interface.source is not None: visit(interface.source)
        active.remove(name)
        emitted.add(name)
        results.append(output)

    visit(path)
    return '\n'.join(results)


def main(argv):
    defines, files, assertions, hierarchy = [], [], False, False
    it = iter(argv)
    for a in it:
        if a == '-D': defines.append(next(it))
        elif a == '--assertions': assertions = True
        elif a == '--hierarchy': hierarchy = True
        else: files.append(a)
    if len(files) != 1:
        print(__doc__, file=sys.stderr); return 2
    try:
        sys.stdout.write(translate(files[0], defines, assertions, hierarchy))
    except (NotImplementedError, ValueError, NameError, SyntaxError, OSError) as exc:
        print('%s: %s: %s' % (files[0], type(exc).__name__, exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
