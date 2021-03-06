# `compiler.coffee` transforms an AST into JavaScript code.

parser = require './parser'
vocabulary = require './vocabulary'
{inherit, assert, all} = require './helpers'
{SyntaxError} = require './errors'

# # Stage 1: Resolve expr nodes

# During this phase we determine the type of each pronoun ('symbol' node) from
# each scope ('body' node).
#
# A pronoun can have either of two types:
#   * Type 'X': data or a niladic function
#   * Type 'F': a verb, adverb, or conjunction
#
# This information is then used to convert each sequence ('expr' node) into
# a hierarchy of function applications ('monadic' or 'dyadic' nodes).
#
# For instance, before this stage, the AST for "1 2 + * 3" is
#
#     ['body',
#       ['expr',
#         ['number', '1'],
#         ['number', '2'],
#         ['symbol', '+'],
#         ['symbol', '*'],
#         ['number', '3']]]
#
# and after resolveExprs() it becomes
#
#     ['body',
#       ['dyadic',
#         ['vector',
#           ['number', '1'],
#           ['number', '2']],
#         ['symbol', '+'],
#         ['monadic',
#           ['number', '*'],
#           ['number', '3']]]]
#
# To see a textual representation of this tree in your shell, type
#   apl -n filename.apl
resolveExprs = (ast, opts = {}) ->
  ast.vars =
    '⍺': {type: 'X', jsCode: '_a'}
    '⍵': {type: 'X', jsCode: '_w'}
    '∇': {type: 'F', jsCode: 'arguments.callee'}
  for k, v of opts.ctx
    ast.vars[k] = varInfo = {type: 'X', jsCode: "_[#{JSON.stringify k}]"}
    if typeof v is 'function'
      varInfo.type = 'F'
      if (m = v.aplMetaInfo)?
        if m.isPrefixAdverb  then varInfo.isPrefixAdverb  = true
        if m.isPostfixAdverb then varInfo.isPostfixAdverb = true
        if m.isConjunction   then varInfo.isConjunction   = true
      if /^[gs]et_.*/.test k
        ast.vars[k[4...]] = {type: 'X'}
  if opts.vars
    for v in opts.vars
      ast.vars[v.name] = {type: 'X', jsCode: v.name}
  ast.scopeDepth = 0
  if opts.exposeTopLevelScope
    ast.scopeObjectJS = '_'
    ast.scopeInitJS = ''
  else
    ast.scopeObjectJS = '_0'
    ast.scopeInitJS = "var _0 = {}"
  queue = [ast] # accumulates "body" nodes which we encounter on our way
  while queue.length
    {vars} = scopeNode = queue.shift()

    visit = (node) ->
      node.scopeNode = scopeNode
      switch node[0]
        when 'body'
          node.vars = inherit vars
          node.scopeDepth = scopeNode.scopeDepth + 1
          node.scopeObjectJS = '_' + node.scopeDepth
          node.scopeInitJS = "var #{node.scopeObjectJS} = {}"
          queue.push node
          null
        when 'guard'
          visit node[1]
          visit node[2]
        when 'assign'
          if not (node[1] instanceof Array and node[1][0] is 'symbol')
            compilerError node, opts, 'Compound assignment is not supported.'
          name = node[1][1]
          assert typeof name is 'string'
          h = visit node[2]
          if vars[name]
            if vars[name].type isnt h.type
              compilerError node, opts,
                "Inconsistent usage of symbol '#{name}', it is " +
                "assigned both data and functions."
          else
            vars[name] =
              type: h.type
              jsCode: "#{scopeNode.scopeObjectJS}[#{JSON.stringify name}]"
          h
        when 'symbol'
          name = node[1]
          if (v = vars["get_#{name}"])?.type is 'F'
            v.used = true
            {type: 'X'}
          else
            v = vars[name]
            if not v
              compilerError node, opts,
                "Symbol '#{name}' is referenced before assignment."
            v.used = true
            v
        when 'lambda'
          visit node[1]
          {type: 'F'}
        when 'string', 'number', 'embedded'
          {type: 'X'}
        when 'index'
          for c in node[2...] when c isnt null
            t = visit c
            if t.type isnt 'X'
              compilerError node, opts,
                'Only expressions of type data can be used as an index.'
          visit node[1]
        when 'expr'
          a = node[1...]
          h = Array a.length
          for i in [a.length - 1 .. 0]
            h[i] = visit a[i]

          # Form vectors from sequences of data
          i = 0
          while i < a.length - 1
            if h[i].type is h[i + 1].type is 'X'
              j = i + 2
              while j < a.length and h[j].type is 'X' then j++
              a[i...j] = [['vector'].concat a[i...j]]
              h[i...j] = [{type: 'X'}]
            else
              i++

          # Apply conjunctions
          i = a.length - 2
          while --i >= 0
            if (h[i + 1].isConjunction and
                (h[i].type is 'F' or h[i + 2].type is 'F'))
              a[i...i+3] = [['conjunction'].concat a[i...i+3]]
              h[i...i+3] = [{type: 'F'}]
              i--

          # Apply postfix adverbs
          i = 0
          while i < a.length - 1
            if h[i].type is 'F' and h[i + 1].isPostfixAdverb
              a[i...i+2] = [['postfixAdverb'].concat a[i...i+2]]
              h[i...i+2] = [{type: 'F'}]
            else
              i++

          # Apply prefix adverbs
          i = a.length - 1
          while --i >= 0
            if h[i].isPrefixAdverb and h[i + 1].type is 'F'
              a[i...i+2] = [['prefixAdverb'].concat a[i...i+2]]
              h[i...i+2] = [{type: 'F'}]

          # Hooks
          if h.length is 2 and h[0].type is h[1].type is 'F'
            a = [['hook'].concat a]
            h = [{type: 'F'}]

          # Forks
          if (h.length >= 3 and h.length % 2 is 1 and
                  all(for x in h then x.type is 'F'))
            a = [['fork'].concat a]
            h = [{type: 'F'}]

          if h[h.length - 1].type is 'F'
            if h.length > 1
              compilerError a[h.length - 1], opts,
                'Trailing function in expression'
          else
            # Apply monadic and dyadic functions
            while h.length > 1
              if h.length is 2 or h[h.length - 3].type is 'F'
                a[h.length - 2...] = [['monadic'].concat a[h.length - 2...]]
                h[h.length - 2...] = [{type: 'X'}]
              else
                a[h.length - 3...] = [['dyadic'].concat a[h.length - 3...]]
                h[h.length - 3...] = [{type: 'X'}]

          # Replace `"expr"` node with `a[0]` in the AST
          node[0...] = a[0]
          h[0]

        else
          assert false, "Unrecognised node type, '#{node[0]}'"

    for node in scopeNode[1...]
      visit node

  return



# # Stage 2: Render JavaScript code
toJavaScript = (node) ->
  switch node[0]

    when 'body'
      if node.length is 1
        'return [];\n'
      else
        a = [node.scopeInitJS]
        for child in node[1...] then a.push toJavaScript child
        a[a.length - 1] = "return #{a[a.length - 1]};"
        a.join ';\n'

    when 'guard'
      """
        if (_._bool(#{toJavaScript node[1]})) {
          return #{toJavaScript node[2]};
        }
      """

    # Assignment
    #
    # A←5     <=> 5
    # A×A←2 5 <=> 4 25
    when 'assign'
      if not (node[1] instanceof Array and
              node[1].length is 2 and
              node[1][0] is 'symbol')
        compilerError node, opts,
          'Compound assignment is not supported.'
      name = node[1][1]
      assert typeof name is 'string'
      if name is '∇'
        compilerError node, opts,
          'Assignment to ∇ is not allowed.'
      vars = node.scopeNode.vars
      if (v = vars["set_#{name}"])?.type is 'F'
        v.used = true
        "#{v.jsCode}(#{toJavaScript node[2]})" # todo: pass-through value
      else
        "#{vars[name].jsCode} = #{toJavaScript node[2]}"

    # Symbols
    #
    # Test get_/set_ convention for niladics:
    #
    # radius ← 3
    # ... get_circumference ← {2×○radius}
    # ... get_surface ← {○radius*2}
    # ...
    # ... before ← 0.01× ⌊ 100× radius circumference surface
    # ... radius ← radius + 1
    # ... after  ← 0.01× ⌊ 100× radius circumference surface
    # ...
    # ... before after
    # ... <=> (3 18.84 28.27)(4 25.13 50.26)
    when 'symbol'
      name = node[1]
      vars = node.scopeNode.vars
      if (v = vars["get_#{name}"])?.type is 'F'
        v.used = true
        "#{v.jsCode}()"
      else
        v = vars[name]
        v.used = true
        v.jsCode

    # Lambda expressions
    #
    # {1 + 1} 1                    <=> 2
    # {⍵=0:1 ⋄ 2×∇⍵-1} 5           <=> 32 # two to the power of
    # {⍵<2 : 1 ⋄ (∇⍵-1)+(∇⍵-2) } 8 <=> 34 # Fibonacci sequence
    when 'lambda'
      """
        function (_w, _a) {
          #{toJavaScript node[1]}
        }
      """

    # Strings of length one are scalars, all other strings are vectors.
    #
    # ⍴⍴''   <=> ,1
    # ⍴⍴'x'  <=> ,0
    # ⍴⍴'xx' <=> ,1
    #
    # Pairs of quotes inside strings:
    #
    # 'Let''s parse it!'        <=> 'Let\'s parse it!'
    # "0x22's the code for ""." <=> '0x22\'s the code for ".'
    # ⍴"\f\t\n\r\u1234\xff"     <=> ,6
    #
    # "unclosed string !!!
    when 'string'
      s = node[1]
      d = s[0] # the delimiter: '"' or "'"
      "_._aplify(#{d + s[1...-1].replace(///#{d + d}///g, '\\' + d) + d})"


    # Numbers
    #
    # 1234567890  <=> «1234567890»
    # 12.34e56    <=> «12.34e56»
    # 12.34e+56   <=> «12.34e+56»
    # 12.34E56    <=> «12.34e56»
    # ¯12.34e¯56  <=> «-12.34e-56»
    # 0Xffff      <=> «0xffff»
    # ¯0xffff     <=> «-0xffff»
    # ¯0xaBcD1234 <=> «-0xabcd1234»
    # ¯           <=> «Infinity»
    # ¯¯          <=> «-Infinity»
    # -¯          <=> «-Infinity»
    when 'number'
      s = node[1].replace /¯/g, '-'
      a =
        for x in s.split /j/i
          if x is '-'
            'Infinity'
          else if x is '--'
            '-Infinity'
          else if x.match /^-?0x/i
            parseInt x, 16
          else
            parseFloat x
      if a.length is 1 or a[1] is 0
        "_._aplify(#{a[0]})"
      else
        "new _._complex(#{a[0]}, #{a[1]})"

    # We translate square-bracket indexing (`A[B]`) to indexing using the
    # squish quad function (`B⌷A`).  The arguments are reversed in the process,
    # so `B` gets evaluated before `A` as one would expect from APL's
    # right-to-left order of execution.
    #
    # ⍴ x[⍋x←6?40] <=> ,6
    when 'index'
      "_._index(
        _._aplify([#{(for c in node[2...] when c then toJavaScript c).join ', '}]),
        #{toJavaScript node[1]},
        _._aplify([#{(for c, i in node[2...] when c isnt null then i)}])
      )"

    when 'expr'
      assert false, 'No "expr" nodes are expected at this stage.'

    when 'vector'
      n = node.length - 1
      "_._aplify([#{
        (for child in node[1...] then toJavaScript child).join ', '
      }])"

    when 'monadic'
      "#{toJavaScript node[1]}(#{toJavaScript node[2]})"

    when 'dyadic'
      "#{toJavaScript node[2]}(#{toJavaScript node[3]}, #{toJavaScript node[1]})"

    when 'prefixAdverb'
      "#{toJavaScript node[1]}(#{toJavaScript node[2]})"

    when 'conjunction'
      "#{toJavaScript node[2]}(#{toJavaScript node[3]}, #{toJavaScript node[1]})"

    when 'postfixAdverb'
      "#{toJavaScript node[2]}(#{toJavaScript node[1]})"

    when 'hook'
      "_._hook(#{toJavaScript node[2]}, #{toJavaScript node[1]})"

    when 'fork'
      "_._fork([#{for c in node[1...] then toJavaScript c}])"

    # Embedded JavaScript
    #
    # «1234+5678» <=> 6912
    # «"asdf"»    <=> 'asdf'
    when 'embedded'
      "_._aplify(#{node[1].replace /(^«|»$)/g, ''})"

    else
      assert false, "Unrecognised node type, '#{node[0]}'"

# Used to report the AST node where the error happened
compilerError = (node, opts, message) ->
  throw SyntaxError message,
    file: opts.file
    line: node.startLine
    col: node.startCol
    aplCode: opts.aplCode

# # Public interface to this module

@nodes = nodes = (aplCode, opts = {}) ->
  opts.aplCode = aplCode
  opts.ctx ?= inherit vocabulary
  ast = parser.parse aplCode, opts
  resolveExprs ast, opts
  ast

@compile = compile = (aplCode, opts = {}) ->
  opts.aplCode = aplCode
  ast = nodes aplCode, opts
  if opts.exposeTopLevelScope
    ast.scopeObjectJS = '_'
  jsCode = toJavaScript ast
  if opts.embedded
    jsCode = """
      var _ = require('apl').createGlobalContext(),
          _a = arguments[0],
          _w = arguments[1];
      #{jsCode}
    """
  jsCode

@exec = (aplCode, opts = {}) ->
  opts.aplCode = aplCode
  jsCode = compile aplCode, opts
  (new Function """
    var _ = arguments[0];
    #{jsCode}
  """) opts.ctx
