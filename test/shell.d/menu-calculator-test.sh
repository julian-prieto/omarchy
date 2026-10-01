#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')

assertEqual(menu.calcEvaluate('10+2'), 12, 'calculator adds')
assertEqual(menu.calcEvaluate('10 + 2'), 12, 'calculator skips spaces')
assertEqual(menu.calcEvaluate('(2+3)*4'), 20, 'calculator groups with parentheses')
assertEqual(menu.calcEvaluate('2^10'), 1024, 'calculator raises to a power')
assertEqual(menu.calcEvaluate('-5+3'), -2, 'calculator applies a leading minus')
assertEqual(menu.calcEvaluate('--5'), 5, 'calculator stacks unary minus')
assertEqual(menu.calcEvaluate('-2^2'), -4, 'calculator binds unary minus looser than power')
assertEqual(menu.calcEvaluate('10%3'), 1, 'calculator takes the remainder')
assertEqual(menu.calcEvaluate('3.5*2'), 7, 'calculator multiplies decimals')
assertEqual(menu.calcEvaluate('2×3'), 6, 'calculator accepts × as typed')
assertEqual(menu.calcEvaluate('1.5^2'), 2.25, 'calculator raises decimals to a power')

assertEqual(menu.calcEvaluate('10+'), null, 'calculator rejects a trailing operator')
assertEqual(menu.calcEvaluate('2*(3+4/(2-2))'), null, 'calculator rejects division by zero')
assertEqual(menu.calcEvaluate('sqrt(4)'), null, 'calculator rejects what is not arithmetic')
assertEqual(menu.calcEvaluate('abc'), null, 'calculator rejects words')
assertEqual(menu.calcEvaluate(''), null, 'calculator rejects an empty expression')
assertEqual(menu.calcEvaluate('10 20'), null, 'calculator rejects a trailing operand')
assertEqual(menu.calcEvaluate('2*(3+4'), null, 'calculator rejects an unbalanced parenthesis')

assertEqual(menu.calcFormat(menu.calcEvaluate('0.1+0.2')), '0.3', 'calculator drops float noise')
assertEqual(menu.calcFormat(menu.calcEvaluate('100/3')), '33.3333333333', 'calculator rounds through 12 significant digits')
assertEqual(menu.calcFormat(menu.calcEvaluate('1000000*1000000')), '1000000000000', 'calculator keeps large products plain')
assertEqual(menu.calcFormat(1e-12), '1e-12', 'calculator switches small values to exponent notation')
assertEqual(menu.calcFormat(Infinity), '', 'calculator formats what cannot be shown as nothing')

assert(
  /function calcEvaluate\(expr\) \{\s*\n\s*return MenuModel\.calcEvaluate\(expr\)\s*\n\s*\}/.test(menuQml)
    && /function calcFormat\(value\) \{\s*\n\s*return MenuModel\.calcFormat\(value\)\s*\n\s*\}/.test(menuQml),
  'menu delegates calculator evaluation to the shared model'
)
assert(
  /if \(query\.charAt\(0\) === "="\) \{[\s\S]*?var calcValue = root\.calcEvaluate\(calcExpr\)/.test(menuQml),
  'menu evaluates a query that starts with = instead of searching it'
)
assert(
  /action: "wl-copy " \+ Util\.shellQuote\(calcText\)/.test(menuQml),
  'menu copies the result to the clipboard when the row runs'
)
JS

pass "menu calculator answers =-prefixed queries"
