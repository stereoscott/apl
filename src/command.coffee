# `command.coffee` contains the `main()` entry point to the APL compiler when
# invoked as a shell command.
#
# Our command-line interface closely follows the design of
# [that of CoffeeScript](http://coffeescript.org/#usage)

optimist = require 'optimist'
fs = require 'fs'
{nodes, compile, exec} = require './compiler'

@main = ->

  # We use [optimist](https://github.com/substack/node-optimist#readme) to
  # parse the arguments.
  {argv} = optimist
    .usage('''
      Usage: apl [options] path/to/script.apl [args]\n
      If called without options, `apl` will run your script.
    ''')
    .describe
      c: 'compile to JavaScript and save as .js files'
      h: 'display this help message'
      i: 'run an interactive APL REPL'
      n: 'print out the parse tree that the parser produces'
      p: 'print out the compiled JavaScript'
      s: 'listen for and compile scripts over stdio'
    .alias
      c: 'compile'
      h: 'help'
      i: 'interactive'
      n: 'nodes'
      p: 'print'
      s: 'stdio'
    .boolean('chinps'.split '')

  # Show help, if requested.
  if argv.help then return optimist.showHelp()

  # Complain about unknown or incompatible options.
  knownOptions =
    'c compile h help i interactive n nodes p print s stdio _'.split ' '
  for k of argv when (k not in knownOptions) and not k.match /^\$\d+/
    process.stderr.write "Unknown option, \"#{k}\"\n\n"
    optimist.showHelp()
    return

  if (argv.interactive and
        (argv.compile or argv.nodes or argv.print or argv.stdio))
    process.stderr.write '''
      Option -i (--interactive) is incompatible with the following options:
        -c, --compile
        -n, --nodes
        -p, --print
        -s, --stdio\n\n
    '''
    optimist.showHelp()
    return

  if argv.interactive and argv._.length
    process.stderr.write '''
      Option -i (--interactive) cannot be used with positional arguments.\n\n
    '''
    optimist.showHelp()
    return

  # Prepare for compilation/execution, create a context object.
  {inherit} = require './helpers'
  vocabulary = require './vocabulary'
  ctx = inherit vocabulary,
    '⍵': for a in argv._ then a.split ''

  # Start a REPL if requested or if no input is specified.
  if argv.interactive or not (argv._.length or argv.stdio)
    return repl ctx

  # Determine input.
  opts = {}
  if argv.stdio
    opts.file = '<stdin>'
    aplCode =
      Buffer.concat(loop # read all of stdin
        b = new Buffer 1024
        k = fs.readSync 0, b, 0, b.length, null
        break unless k
        b.slice 0, k
      ).toString 'utf8'
  else
    opts.file = argv._[0]
    aplCode = fs.readFileSync opts.file, 'utf8'

  # If printing of nodes is requested, do it and stop.
  if argv.nodes
    printAST nodes aplCode, opts
    return

  # Compile.
  jsCode = compile aplCode, opts

  # Print or execute compiler output
  #
  # (it looks a little hairy because we must wrap compiler output differently
  # depending on where it will be executed, but really it's straightforward)
  if argv.compile
    jsCode = """
      \#!/usr/bin/env node
      var _ = require('apl').createGlobalContext();
      #{jsCode}
    """
    if argv.stdio or argv.print
      process.stdout.write jsCode
    else
      filename = argv._[0].replace(/\.(apl|coffee)$/, '.js')
      fs.writeFileSync filename, jsCode, 'utf8'
  else
    (new Function """
      var _ = arguments[0];
      #{jsCode}
    """) require('./apl').createGlobalContext()



# Read-eval-print loop
repl = (ctx) ->
  readline = require 'readline'
  rl = readline.createInterface process.stdin, process.stdout
  rl.setPrompt 'APL> '

  {format} = require('./vocabulary/format')
  rl.on 'line', (line) ->
    try
      if not line.match /^[\ \t\f\r\n]*$/
        result = exec line, ctx: ctx, exposeTopLevelScope: true
        process.stdout.write format(result).join('\n') + '\n'
    catch e
      console.error e
    rl.prompt()
    return

  rl.on 'close', ->
    process.stdout.write '\n'
    process.exit 0
    return

  rl.prompt()
  return



# Helper functions for printing AST nodes
printAST = (x, indent = '') ->
  if isArray x
    if x.length is 2 and not isArray x[1]
      console.info indent + x[0] + ' ' + JSON.stringify x[1]
    else
      console.info indent + x[0]
      for y in x[1...]
        printAST y, indent + '  '
  else
    console.info indent + JSON.stringify x
  return

isArray = (x) -> x?.length? and typeof x isnt 'string'
