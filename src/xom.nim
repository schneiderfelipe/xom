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
    node: XmlNode ## The XML represented by the object.
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


func initXom*(node: XmlNode): Xom {.compileTime.} =
  ## Initialize a `Xom` object with a `XmlNode`. Default behavior of all
  ## callbacks is to emit code to create nodes.
  result = Xom(node: node)
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


func flushBufferTo(stmts, nnode: NimNode, context: Xom) {.compileTime.} =
  ## Flush the buffer of a `Xom` object by adding code to `result` to produce
  ## a text node attached to `nnode` with the buffer contents. Do nothing if the
  ## buffer is empty.
  if len(context.buffer) > 0:
    stmts.add superQuote do:
      `nnode`.appendChild(document.createTextNode(`adjustText(context.buffer)`))
    context.buffer = ""
    assert len(context.buffer) == 0, "Buffer not empty after flush"


func createIdentFor(node: XmlNode, context: Xom): NimNode {.compileTime.} =
  ## Create a cute unique identifier for an XML node in the form
  ## `"<char><id>"`, where "`<char>`" is the first letter of the tag name and
  ## "`<id>`" is a an increasing number starting at zero.
  let c = case node.kind:
  of xnElement:
    node.tag[0]
  of xnText:
    't'
  else:
    raise newException(ValueError, "unsupported XML node kind: " & $node.kind)
  result = ident(c & $context.id[c])
  context.id.inc(c)


proc toNimNodeImpl(node: XmlNode, context: Xom,
    assigns: NimNode): NimNode {.compileTime.} =
  ## Create a `NimNode` that constructs an HTML element with the same
  ## structure as `x` by using DOM calls, and use the context of the `Xom`
  ## object `q`. HTML comments are ignored and, if the whole tree is ignored,
  ## a `NimNode` representing `nil` is returned.
  case node.kind:
  of xnElement:
    let enterCommand = context.onEnter(node)
    if enterCommand == Discard:
      return newNilLit()

    result = superQuote do:
      document.createElement(`node.tag`)

    if len(node) > 0 or attrsLen(node) > 0 or enterCommand == EmitNamed:
      let nnode = createIdentFor(node, context)
      if enterCommand != EmitNamed:
        result = newStmtList quote do:
          let `nnode` = `result`
      else:
        context.onEmitNamed(node, nnode)
        assigns.add quote do:
          let `nnode` = `result`
        result = newStmtList()

      if not isNil(node.attrs):
        for key, value in node.attrs:
          result.add quote do:
            `nnode`.setAttribute(`key`, `value`)

      for child in node:
        case child.kind:
        of xnElement:
          flushBufferTo(result, nnode, context)
          let nchild = toNimNodeImpl(child, context, assigns)
          if nchild.kind != nnkNilLit:
            result.add quote do:
              `nnode`.appendChild(`nchild`)
        of xnText:
          let enterCommand = context.onEnter(child)
          if enterCommand == Discard:
            continue

          if enterCommand != EmitNamed:
            context.buffer &= child.text
          else:
            flushBufferTo(result, nnode, context)
            let text = createIdentFor(child, context)
            context.onEmitNamed(child, text)
            assigns.add superQuote do:
              let `text` = document.createTextNode(`adjustText(child.text)`)
            result.add quote do:
              `nnode`.appendChild(`text`)
        of xnComment:
          continue
        else:
          raise newException(ValueError, "unsupported XML node kind: " & $child.kind)

      flushBufferTo(result, nnode, context)
      result.add nnode
  of xnText:
    let enterCommand = context.onEnter(node)
    if enterCommand == Discard:
      return newNilLit()

    result = superQuote do:
      document.createTextNode(`adjustText(node.text)`)

    if enterCommand == EmitNamed:
      let nnode = createIdentFor(node, context)
      context.onEmitNamed(node, nnode)
      assigns.add quote do:
        let `nnode` = `result`
      result = nnode
  of xnComment:
    return newNilLit()
  else:
    raise newException(ValueError, "unsupported XML node kind: " & $node.kind)


converter toNimNode(node: Xom): NimNode {.compileTime.} =
  ## Convert a `Xom` object to a `NimNode`. This converter constructs an HTML
  ## element with the same structure as `x` by using DOM calls. HTML comments
  ## are ignored and, if the whole tree is ignored, a `NimNode` representing
  ## `nil` is returned.
  let assigns = newStmtList()
  result = toNimNodeImpl(node.node, node, assigns)
  if len(assigns) > 0:
    for i, assign in assigns:
      result.insert i, assign
