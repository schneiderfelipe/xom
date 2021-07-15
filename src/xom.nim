when not defined(js) and not defined(Nimdoc):
  {.error: "This module only works on the JavaScript platform".}

import dom, macros, macroutils, strtabs, strutils, sugar,
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
    onEmitNamed*: (XmlNode, NimNode) -> void
      ## Callback called when code for a named node is emitted (i.e., with
      ## `createElement` or `createTextNode` and eventually later
      ## `setAttribute` and `appendChild`). It receives both the node and its
      ## variable name as a parameter.


func initXom*(x: XmlNode): Xom {.compileTime.} =
  ## Initialize a `Xom` object with a `XmlNode`. Default behavior of all
  ## callbacks is to emit code to create nodes.
  result = Xom(tree: x)
  result.onEnter = func(node: XmlNode): Command =
    Emit
  result.onEmitNamed = func(node: XmlNode, name: NimNode) =
    assert len(name.strVal) > 0, "Named nodes must have a name"


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


func flushBufferTo(stmts, n: NimNode, context: Xom) {.compileTime.} =
  ## Flush the buffer of a `Xom` object by adding code to `result` to produce
  ## a text node attached to `n` with the buffer contents. Do nothing if the
  ## buffer is empty.
  if len(context.buffer) > 0:
    stmts.add superQuote do:
      `n`.appendChild(document.createTextNode(`adjustText(context.buffer)`))
    context.buffer = ""
    assert len(context.buffer) == 0, "Buffer not empty after flush"


func createIdentFor(x: XmlNode, context: Xom): NimNode {.compileTime.} =
  ## Create a cute unique identifier for an XML node in the form
  ## `"<char><id>"`, where "`<char>`" is the first letter of the tag name and
  ## "`<id>`" is a an increasing number starting at zero.
  let c = case x.kind:
  of xnElement:
    x.tag[0]
  of xnText:
    't'
  else:
    raise newException(ValueError, "unsupported XML node kind: " & $x.kind)
  result = ident(c & $context.id[c])
  context.id.inc(c)


proc toNimNodeImpl(x: XmlNode, context: Xom,
    assigns: NimNode): NimNode {.compileTime.} =
  ## Create a `NimNode` that constructs an HTML element with the same
  ## structure as `x` by using DOM calls, and use the context of the `Xom`
  ## object `q`. HTML comments are ignored and, if the whole tree is ignored,
  ## a `NimNode` representing `nil` is returned.
  case x.kind:
  of xnElement:
    let enterCommand = context.onEnter(x)
    if enterCommand == Discard:
      return newNilLit()

    result = superQuote do:
      document.createElement(`x.tag`)

    if len(x) > 0 or attrsLen(x) > 0 or enterCommand == EmitNamed:
      let n = createIdentFor(x, context)
      if enterCommand != EmitNamed:
        result = newStmtList quote do:
          let `n` = `result`
      else:
        context.onEmitNamed(x, n)
        assigns.add quote do:
          let `n` = `result`
        result = newStmtList()

      if not isNil(x.attrs):
        for key, value in x.attrs:
          result.add quote do:
            `n`.setAttribute(`key`, `value`)

      for xchild in x:
        case xchild.kind:
        of xnElement:
          flushBufferTo(result, n, context)
          let nchild = toNimNodeImpl(xchild, context, assigns)
          if nchild.kind != nnkNilLit:
            result.add quote do:
              `n`.appendChild(`nchild`)
        of xnText:
          let enterCommand = context.onEnter(xchild)
          if enterCommand == Discard:
            continue

          if enterCommand != EmitNamed:
            context.buffer &= xchild.text
          else:
            flushBufferTo(result, n, context)
            let t = createIdentFor(xchild, context)
            context.onEmitNamed(xchild, t)
            assigns.add superQuote do:
              let `t` = document.createTextNode(`adjustText(xchild.text)`)
            result.add quote do:
              `n`.appendChild(`t`)
        of xnComment:
          continue
        else:
          raise newException(ValueError, "unsupported XML node kind: " & $xchild.kind)

      flushBufferTo(result, n, context)
      result.add n
  of xnText:
    let enterCommand = context.onEnter(x)
    if enterCommand == Discard:
      return newNilLit()

    result = superQuote do:
      document.createTextNode(`adjustText(x.text)`)

    if enterCommand == EmitNamed:
      let n = createIdentFor(x, context)
      context.onEmitNamed(x, n)
      assigns.add quote do:
        let `n` = `result`
      result = n
  of xnComment:
    return newNilLit()
  else:
    raise newException(ValueError, "unsupported XML node kind: " & $x.kind)


converter toNimNode*(x: Xom): NimNode {.compileTime.} =
  ## Convert a `Xom` object to a `NimNode`. This converter constructs an HTML
  ## element with the same structure as `x` by using DOM calls. HTML comments
  ## are ignored and, if the whole tree is ignored, a `NimNode` representing
  ## `nil` is returned.
  let assigns = newStmtList()
  result = toNimNodeImpl(x.tree, x, assigns)
  if len(assigns) > 0:
    for i, assign in assigns:
      result.insert i, assign
