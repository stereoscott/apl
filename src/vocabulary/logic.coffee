{APLArray} = require '../array'
{RankError, DomainError} = require '../errors'
{numeric, pervasive, bool, match} = require './vhelpers'
{assert, isInt} = require '../helpers'

negate = pervasive monad: (x) -> +not bool x

@['~'] = (omega, alpha) ->
  if alpha

    # Without (`~`)
    #
    # "ABCDEFGHIJKLMNOPQRSTUVWXYZ"~"AEIOU" <=> 'BCDFGHJKLMNPQRSTVWXYZ'
    # 1 2 3 4 5 6 ~ 2 4 6                  <=> 1 3 5
    # "THIS IS TEXT" ~ " "                 <=> 'THISISTEXT'
    # "THIS" "AND" "THAT" ~ "T"            <=> 'THIS' 'AND' 'THAT'
    # "THIS" "AND" "THAT" ~ "AND"          <=> 'THIS' 'AND' 'THAT'
    # "THIS" "AND" "THAT" ~ ⊂"AND"         <=> 'THIS' 'THAT'
    # "THIS" "AND" "THAT" ~ "TH" "AND"     <=> 'THIS' 'THAT'
    #
    # 11 12 13 14 15 16 ~ 2 3⍴1 2 3 14 5 6 <=> 11 12 13 15 16
    if alpha.shape.length > 1
      throw RankError()
    data = []
    alpha.each (x) ->
      try
        omega.each (y) -> if match x, y then throw 'break'
        data.push x
      catch e
        if e isnt 'break' then throw e
    new APLArray data

  else

    # Not (`~`)
    #
    # ~0 1 <=> 1 0
    # ~2   !!! DOMAIN ERROR
    negate omega


@['∨'] = pervasive

  # Or (LCM) (`∨`)
  #
  # 1∨1               <=> 1
  # 1∨0               <=> 1
  # 0∨1               <=> 1
  # 0∨0               <=> 0
  # 0 0 1 1 ∨ 0 1 0 1 <=> 0 1 1 1
  # 12∨18             <=> 6   # 12=2×2×3, 18=2×3×3
  # 299∨323           <=> 1   # 299=13×23, 323=17×19
  # 12345∨12345       <=> 12345
  # 0∨123             <=> 123
  dyad: numeric (y, x) ->
    if not (isInt(x, 0) and isInt(y, 0))
      throw DomainError '∨ is implemented only for non-negative integers' # todo
    if x is 0 and y is 0 then return 0
    if x < y then [x, y] = [y, x]
    while y then [x, y] = [y, x % y] # Euclid's algorithm
    x


@['∧'] = pervasive

  # And (GCD) (`∧`)
  #
  # 1∧1                            <=> 1
  # 1∧0                            <=> 0
  # 0∧1                            <=> 0
  # 0∧0                            <=> 0
  # 0 0 1 1∧0 1 0 1                <=> 0 0 0 1
  # 0 0 0 1 1∧1 1 1 1 0            <=> 0 0 0 1 0
  # t←3 3⍴1 1 1 0 0 0 1 0 1 ⋄ 1∧t  <=> 3 3 ⍴ 1 1 1 0 0 0 1 0 1
  # t←3 3⍴1 1 1 0 0 0 1 0 1 ⋄ ∧/t  <=> 1 0 0
  # 12∧18   # 12=2×2×3, 18=2×3×3   <=> 36
  # 299∧323 # 299=13×23, 323=17×19 <=> 96577
  # 12345∧12345                    <=> 12345
  # 0∧123                          <=> 0
  dyad: numeric (y, x) ->
    assert x is Math.floor(x) and y is Math.floor(y), '∧ is defined only for integers'
    if x is 0 or y is 0 then return 0
    p = x * y
    if x < y then [x, y] = [y, x]
    while y then [x, y] = [y, x % y] # Euclid's algorithm
    p / x # LCM(x, y) = x * y / GCD(x, y)


# Nor (`⍱`)
#
# 0⍱0 <=> 1
# 0⍱1 <=> 0
# 1⍱0 <=> 0
# 1⍱1 <=> 0
# 0⍱2 !!! DOMAIN ERROR
@['⍱'] = pervasive dyad: numeric (y, x) -> +!(bool(x) | bool(y))

# Nand (`⍲`)
#
# 0⍲0 <=> 1
# 0⍲1 <=> 1
# 1⍲0 <=> 1
# 1⍲1 <=> 0
# 0⍲2 !!! DOMAIN ERROR
@['⍲'] = pervasive dyad: numeric (y, x) -> +!(bool(x) & bool(y))
