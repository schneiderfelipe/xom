when not defined(js) and not defined(Nimdoc):
  {.error: "This module only works on the JavaScript platform".}

import dom, macros, macroutils, strformat, strtabs, strutils, sugar,
    tables, xmltree


type
  Command* = enum
    ## Return type for callbacks.
    Emit,      ## Emit code to create the node (default behavior).
    EmitNamed, ## emit code to create the node, and also create a variable
               ## for it.
    Discard,   ## Discard the node and its children and don't emit any code.

  Xom = ref object
    ## An object holding context for a conversion between `XmlNode` and
    ## `NimNode`. It accepts some callbacks, which serve as transformers,
    ## since the given object can be modified prior to this generation.
    tree: XmlNode ## The XML represented by the object.
    id: CountTable[char] ## Keep track of how many elements of each type were already generated.
    buffer: string ## Buffer used during aglutination of text nodes.
    onEnter*: XmlNode -> Command
      ## Callback called when a new node is found. It receives the node as
      ## a parameter, and returns a command to be performed on it. The default
      ## behavior is to emit code to create the node. The command can be
      ## `Emit`, `EmitNamed`, or `Discard`. The `Emit` command will emit
      ## code to create the node, and the `EmitNamed` command will emit code
      ## to create the node, and also create a variable for it. The `Discard`
      ## command will not emit any code, and the node will be discarded.
    onEmitCode: (XmlNode, string) -> Command
      ## Callback called when code for a node is emitted (i.e., with
      ## `createElement` or `createTextNode` and eventually later
      ## `setAttribute` and `appendChild`). It receives the node as a
      ## parameter, and returns a command to be performed on it. The default
      ## behavior is to emit code to create the node. The command can be
      ## `Emit`, `EmitNamed`, or `Discard`. Both `Emit` and `EmitNamed`
      ## commands will emit code to create the node. The `Discard` command
      ## will not emit any code, and the node will be discarded.


func initXom*(x: XmlNode): Xom {.compileTime.} =
  ## Initialize a `Xom` object with a `XmlNode`. Default behavior of all
  ## callbacks is to emit code to create nodes.
  result = Xom(tree: x)
  result.onEnter = func(node: XmlNode): Command =
    Emit
  result.onEmitCode = func(node: XmlNode, name: string = ""): Command =
    Emit


func adjustText(s: string): string {.compileTime.} =
  ## Remove whitespace from `s` as much as possible, hopefully not breaking
  ## any HTML rule. Basically, contigous whitespace is transformed into
  ## single `' '` characters.
  let start = low(s)

  if len(s) > 0:
    if not s[start].isSpaceAscii:
      result &= s[start]
    else:
      result &= ' '

  for i in start+1..high(s):
    if not s[i].isSpaceAscii:
      result &= s[i]
    elif not s[i-1].isSpaceAscii:
      result &= ' '


func flushBufferTo(stmts, n: NimNode, q: Xom) {.compileTime.} =
  ## Flush the buffer of a `Xom` object by adding code to `result` to produce
  ## a text node attached to `n` with the buffer contents. Do nothing if the
  ## buffer is empty.
  if len(q.buffer) > 0:
    stmts.add superQuote do:
      `n`.appendChild(document.createTextNode(`adjustText(q.buffer)`))
    q.buffer = ""
    assert len(q.buffer) == 0


func createIdentFor(x: XmlNode, q: Xom): auto {.compileTime.} =
  ## Create a cute unique identifier for an XML node in the form
  ## `"<char><id>"`, where "`<char>`" is the first letter of the tag name and
  ## "`<id>`" is a an increasing number starting at zero.
  let c = x.tag[0]
  result = ident(&"{c}{q.id[c]}")
  q.id.inc(c)


proc toNimNodeImpl(x: XmlNode, q: Xom): NimNode {.compileTime.} =
  ## Create a `NimNode` that constructs an HTML element with the same
  ## structure as `x` by using DOM calls, and use the context of the `Xom`
  ## object `q`. HTML comments are ignored and, if the whole tree is ignored,
  ## a `NimNode` representing `nil` is returned.
  case x.kind:
  of xnElement, xnText:
    let command = q.onEnter(x)
    if command == Discard:
      return
  else:
    discard

  case x.kind:
  of xnElement:
    result = superQuote do:
      document.createElement(`x.tag`)

    if len(x) > 0 or attrsLen(x) > 0:
      let n = createIdentFor(x, q)

      result = newStmtList quote do:
        let `n` = `result`

      if not isNil(x.attrs):
        for key, value in x.attrs:
          result.add quote do:
            `n`.setAttribute(`key`, `value`)

      for xchild in x:
        if xchild.kind == xnText:
          q.buffer &= xchild.text
        else:
          flushBufferTo(result, n, q)
          let nchild = toNimNodeImpl(xchild, q)
          if nchild.kind != nnkNilLit:
            result.add quote do:
              `n`.appendChild(`nchild`)

      flushBufferTo(result, n, q)
      result.add n
  of xnText:
    result = superQuote do:
      document.createTextNode(`adjustText(x.text)`)
  of xnComment:
    discard
  else:
    raise newException(ValueError, &"unsupported XML node type: '{x.kind}'")


converter toNimNode*(x: Xom): NimNode {.compileTime.} =
  ## Convert a `Xom` object to a `NimNode`. This converter constructs an HTML
  ## element with the same structure as `x` by using DOM calls. HTML comments
  ## are ignored and, if the whole tree is ignored, a `NimNode` representing
  ## `nil` is returned.
  toNimNodeImpl(x.tree, x)
