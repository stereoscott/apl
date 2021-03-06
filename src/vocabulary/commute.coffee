{assert} = require '../helpers'

# [Commute](http://www.jsoftware.com/papers/opfns1.htm#3) (`⍨`)
#
# Definition: `x f⍨ y  <->  y f x`
#
# 17-⍨23 <=> 6
# 7⍴⍨2 3 <=> 2 3⍴7
# -⍨123  <=> ¯123
@['⍨'] = (f) ->
  assert typeof f is 'function'
  (omega, alpha, axis) ->
    if alpha then f alpha, omega, axis else f omega, undefined, axis
