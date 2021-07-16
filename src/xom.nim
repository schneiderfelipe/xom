## Transform XML trees into performant JavaScript DOM calls at *compile-time*
## using Nim code.
##
## ```nim
## import dom, htmlparser, macros, xom
##
## macro html(s: string{lit}): Node =
##   parseHtml(s.strVal).initXom()
##
## document.body.appendChild html"<p>Hello!</p>"
## ```
##
## In the usage example above, the `html` macro wrappers around the
## `parseHtml` function from `htmlparser`, which takes a string and returns a
## XML tree. But instead of returning the XML tree, we feed it to `initXom`,
## which returns a `Xom` context object. The context object is then
## (implicitly) converted into a `NimNode` object that compiles to DOM API
## calls.
## This particular example compiles to the following JavaScript code:
##
## ```javascript
## var p0 = document.createElement("p");
## p0.appendChild(document.createTextNode("Hello!"));
## document.body.appendChild(p0);
## ```
##
## You can both choose the way you generate a XML tree and customize the
## what the `Xom` context object does behind the scenes.
##
## ## Customizing code generation
##
## xom can be customized to generate code that is optimized for a particular use
## case.
## Nodes can be modified in-place, new child nodes can be created, the code
## generation can be suppressed all together for particular nodes, and variables
## are only created for nodes that you specify.
##
## All this customization is done through the use of the two simple callbacks of
## the `Xom` context object:
## - `onEnter*: XmlNode -> Command`
## - `onEmitNamed*: (XmlNode, NimNode) -> void`
##
## `onEnter` is called for every node that is found, and `onEmitNamed` is
## called for every node for which a variable has been requested.
## `onEnter` returns a `Command` object, which is an enum type that can be one of
## the following:
## - `Emit`: the node will be emitted but no variable will be created (default for
##   all nodes).
## - `EmitNamed`: the node will be emitted and a variable for it will be
##   created. This also triggers a call to `onEmitNamed` on the node.
## - `Skip`: the node will be skipped and no variable will be created.
##
## Inside both callbacks, you can modify nodes in-place, and changes will be
## reflected in the generated code *at compile-time*.
##
## By default, no variables are created for nodes that are not requested *if not
## necessary* (and necessary but not requested variables are always scoped by
## default).
## If you want to reference a node inside `onEmitNamed`, you *have* to return
## `EmitNamed` from `onEnter` for that node.
## In particular, text nodes are always merged together unless a variable is
## being emitted for them.
## Having a variable for a node is useful for dinamically modifying the node in
## separately generated code (see `examples/` and `tests/` for some simple use
## cases).


when not defined(js) and not defined(Nimdoc):
  {.error: "This module only works on the JavaScript platform".}

when defined(js):
  import dom # Required for generating the documentation.

import macros, strtabs, strutils, sugar, tables, xmltree


type
  Command* = enum
    ## Return type for the ``onEnter`` callback of ``Xom`` context objects.
    ##
    ## - ``Emit`` emits code for creating the given node (default behavior).
    ## - ``EmitNamed`` emits code for creating the given node and assigns it to a variable (to be passed to the ``onEmitNamed`` callback).
    ## - ``Skip`` does not emit code for creating the given node (or its children).
    Emit, EmitNamed, Skip

  Xom* = ref object
    ## An object holding context for a conversion between ``XmlNode`` and
    ## ``NimNode``. It accepts two callbacks:
    ##
    ## - ``onEnter`` is called when a node has just been found. It accepts the XML node and returns a ``Command`` to be performed on it. The default behavior is to simply emit code for creating the node.
    ## - ``onEmitNamed`` is called when code and a variable for a node is about to be emitted. It accepts the XML node and the variable (as a ``NimNode``) and returns nothing.
    ##
    ## Inside both callbacks, the XML nodes can be modified as desired.
    tree: XmlNode # The XML tree represented by the object.
    counter: CountTable[char] # A table that keeps track of variable names.
    buffer: string # Buffer used during merging of text nodes.
    onEnter*: XmlNode -> Command
    onEmitNamed*: (XmlNode, NimNode) -> void


func initXom*(tree: XmlNode): Xom {.compileTime.} =
  ## Create a new ``Xom`` context object. The ``tree`` argument is the XML tree
  ## to be converted. The ``onEnter`` and ``onEmitNamed`` callbacks can be
  ## defined later.
  Xom(
    tree: tree,
    onEnter: func(node: XmlNode): Command = Emit,
    onEmitNamed: func(node: XmlNode, name: NimNode) = assert len(name.strVal) >
        0, "Named nodes must have a name"
  )


func adjustText(text: string): string {.compileTime.} =
  ## Adjust the text to remove any doubly white space characters. This is
  ## a helper function that ensures we emit as few text nodes as possible.
  if len(text) > 0:
    if not text[low(text)].isSpaceAscii:
      result &= text[low(text)]
    else:
      result &= ' '
  for i in low(text)+1..high(text):
    if not text[i].isSpaceAscii:
      result &= text[i]
    elif not text[i-1].isSpaceAscii:
      result &= ' '


func flushBufferTo(stmts, nnode: NimNode, context: Xom) {.compileTime.} =
  ## Flush the buffer of a ``Xom`` context object, produce the corresponding
  ## code, insert it into the given ``stmts`` object and flush the buffer.
  if len(context.buffer) > 0:
    let text = adjustText(context.buffer)
    stmts.add quote do:
      `nnode`.appendChild(document.createTextNode(`text`))
    context.buffer = ""
  assert len(context.buffer) == 0, "Buffer not empty after flush"


func createIdentFor(node: XmlNode, context: Xom): NimNode {.compileTime.} =
  ## Create a ``NimNode`` representing a unique variable identifier for the
  ## given ``node``.
  let letter = case node.kind:
  of xnElement:
    node.tag[0]
  of xnText:
    'z' # All variables starting with z represent text nodes since HTML has no tags starting with z.
  else:
    raise newException(ValueError, "unsupported XML node kind: " & $node.kind)
  defer:
    context.counter.inc(letter)
  ident(letter & $context.counter[letter])


proc toNimNodeImpl(node: XmlNode, context: Xom,
    assigns: NimNode): NimNode {.compileTime.} =
  ## Convert the given ``node`` to a ``NimNode`` using the given ``context``. The
  ## ``assigns`` argument is used to keep track of the variables created by the
  ## conversion.
  ##
  ## - If the node is a text node, the result is a call to ``createTextNode``.
  ## - If the node is an element node, the result code produces the corresponding DOM node by calling ``createElement``, ``setAttribute``, and ``appendChild``.
  ## - If the node is a comment node, it is ignored.
  ##
  ## No other node types are supported.
  case node.kind:
  of xnElement:
    let enterCommand = context.onEnter(node)
    if enterCommand == Skip:
      return newNilLit()

    let tag = node.tag
    result = quote do:
      document.createElement(`tag`)

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
          if enterCommand == Skip:
            continue

          if enterCommand != EmitNamed:
            context.buffer &= child.text
          else:
            flushBufferTo(result, nnode, context)
            let ntext = createIdentFor(child, context)
            context.onEmitNamed(child, ntext)
            let text = adjustText(child.text)
            assigns.add quote do:
              let `ntext` = document.createTextNode(`text`)
            result.add quote do:
              `nnode`.appendChild(`ntext`)
        of xnComment:
          continue
        else:
          raise newException(ValueError, "unsupported XML node kind: " & $child.kind)

      flushBufferTo(result, nnode, context)
      result.add nnode
  of xnText:
    let enterCommand = context.onEnter(node)
    if enterCommand == Skip:
      return newNilLit()

    let text = adjustText(node.text)
    result = quote do:
      document.createTextNode(`text`)

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
  assert result.kind != nnkNilLit, "nil result not explicitly returned"


converter toNimNode*(context: Xom): NimNode {.compileTime.} =
  ## Convert the given ``context`` to a ``NimNode`` representing the root node of
  ## the XML tree of the given ``context`` by calling the DOM API.
  ##
  ## HTML comments are ignored and, if the whole document is a comment, the
  ## resulting ``NimNode`` represents ``nil``.
  let assigns = newStmtList()
  result = toNimNodeImpl(context.tree, context, assigns)
  if len(assigns) > 0:
    for i, assign in assigns:
      result.insert i, assign
