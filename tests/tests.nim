import unittest

import xom

import dom, htmlparser, macros, strformat, strutils, xmltree


func avoidNilandPrint(context: NimNode, code: string): NimNode =
  ## Throw `ValueError` if `context` represents `nil`, and prints the
  ## generated code.
  result = context
  if result.kind == nnkNilLit or
      result.findChild(it.kind == nnkNilLit) != nil:
    raise newException(ValueError,
                       "pure XML comments or whitespace found (got nil)")
  debugEcho &"\n\n<!-- The generated code for \"{code}\": -->\n{repr result}"


macro html(s: string{lit}): Node =
  ## Helper for HTML parsing.
  let code = s.strVal
  avoidNilandPrint(parseHtml(code).initXom(), code)


func appendChildAndReturn(parent, child: Node): Node =
  ## Helper for testing DOM manipulation.
  parent.appendChild(child)
  return child


suite "Element basics":
  test "can create empty elements":
    let x = document.body.appendChildAndReturn html"<span></span>"
    check x.nodeName == "SPAN"
    check x.textContent == ""
    check document.body.childNodes[2] == x

  test "can create elements containing distinct elements":
    let x = document.body.appendChildAndReturn html"<h1><span>Hello, world!</span></h1>"
    check x.nodeName == "H1"
    check x.textContent == "Hello, world!"
    check document.body.childNodes[3] == x

    check x.childNodes[0].nodeName == "SPAN"
    check x.childNodes[0].textContent == x.textContent

  test "can create elements containing similar elements":
    let x = document.body.appendChildAndReturn html"<div><div>This is xom, a Nim library that converts XmlNodes into DOM calls at compile-time & is awesome!</div></div>"
    check x.nodeName == "DIV"
    check x.textContent == "This is xom, a Nim library that converts XmlNodes into DOM calls at compile-time & is awesome!"
    check document.body.childNodes[4] == x

    check x.childNodes[0].nodeName == "DIV"
    check x.childNodes[0].textContent == x.textContent


suite "Text basics":
  test "can create text nodes":
    let x = document.body.appendChildAndReturn html"With xom, you can produce performant JavaScript DOM code using high-level Nim code."
    check x.nodeName == "#text"
    check x.textContent == "With xom, you can produce performant JavaScript DOM code using high-level Nim code."
    check document.body.childNodes[5] == x

  test "can create elements containing text":
    let x = document.body.appendChildAndReturn html"<h2>Features</h2>"
    check x.nodeName == "H2"
    check x.textContent == "Features"
    check document.body.childNodes[6] == x

    check x.childNodes[0].nodeName == "#text"
    check x.childNodes[0].textContent == x.textContent

  test "can create elements containing text with entities":
    let x = document.body.appendChildAndReturn html"<p>HTML entities: &lt;, &gt;, &amp;, &quot;.</p>"
    check x.nodeName == "P"
    check x.textContent == "HTML entities: <, >, &, \"."
    check document.body.childNodes[7] == x

    check x.childNodes[0].nodeName == "#text"
    check x.childNodes[0].textContent == x.textContent

    check len(x.childNodes) == 1


suite "Comment basics":
  test "can create elements containing text and ignored comments":
    let x = document.body.appendChildAndReturn html"<p>HTML comments, <!-- not sure if it can be called 'support' then --> but they are ignored (at <strong>compile-time</strong>).</p>"
    check x.nodeName == "P"
    check x.textContent == "HTML comments, but they are ignored (at compile-time)."
    check document.body.childNodes[8] == x

    check x.childNodes[0].nodeName == "#text"
    check x.childNodes[0].textContent == "HTML comments, but they are ignored (at "

    check len(x.childNodes) == 3
    check x.childNodes[^1].nodeName == "#text"
    check x.childNodes[^1].textContent == ")."

  test "comments are unsupported at the top level":
    check not compiles html"<!-- ceci n'est pas un commentaire ?????? -->"


suite "Advanced control":
  test "can insert elements on entering or avoid creation":
    macro html2(s: string{lit}): Node =
      let
        code = s.strVal
        context = parseHtml(code).initXom()
      context.onEnter = proc(x: XmlNode): Command =
        if x.kind == xnElement:
          case x.tag
          of "p":
            x.add newText(" when created.")
          of "span":
            return Skip
          else:
            discard
        Emit # is already the default value for Command
      avoidNilandPrint(context, code)

    let x = document.body.appendChildAndReturn html2"<p>Callbacks for <strong>modifying elements</strong><span>, and removing,</span></p>"
    check x.nodeName == "P"
    check x.textContent == "Callbacks for modifying elements when created."
    check document.body.childNodes[9] == x

    check x.childNodes[0].nodeName == "#text"
    check x.childNodes[0].textContent == "Callbacks for "

    check x.childNodes[1].nodeName == "STRONG"
    check x.childNodes[1].textContent == "modifying elements"

    check len(x.childNodes) == 3
    check x.childNodes[^1].nodeName == "#text"
    check x.childNodes[^1].textContent == " when created."

  test "can modify or ignore attributes on being set":
    macro html2(s: string{lit}): Node =
      let
        code = s.strVal
        context = parseHtml(code).initXom()
      context.onEnter = proc(x: XmlNode): Command =
        if x.kind == xnElement:
          case x.tag
          of "p":
            x.attrs = nil
          of "span":
            x.attrs = {"style": "font-style: italic;"}.toXmlAttributes
          else:
            discard
        # Emit  # is already the default value for Command
      avoidNilandPrint(context, code)

    let x = document.body.appendChildAndReturn html2"<p id=remove-this>Callbacks for <span class=italic>modifying attributes</span>.</p>"
    check x.nodeName == "P"
    check x.textContent == "Callbacks for modifying attributes."
    check document.body.childNodes[10] == x
    check not x.hasAttribute("id")

    check x.childNodes[0].nodeName == "#text"
    check x.childNodes[0].textContent == "Callbacks for "

    check x.childNodes[1].nodeName == "SPAN"
    check x.childNodes[1].textContent == "modifying attributes"
    check x.childNodes[1].getAttribute("style") == "font-style: italic;"
    check not x.childNodes[1].hasAttribute("class")

    check len(x.childNodes) == 3
    check x.childNodes[^1].nodeName == "#text"
    check x.childNodes[^1].textContent == "."


  test "can modify or ignore text nodes on entering":
    macro html2(s: string{lit}): Node =
      let
        code = s.strVal
        context = parseHtml(code).initXom()
      context.onEnter = proc(x: XmlNode): Command =
        if x.kind == xnText:
          if "fnord" in x.text:
            return Skip
          x.text = x.text.replace("XXX", "modifying text nodes")
        # Emit  # is already the default value for Command
      avoidNilandPrint(context, code)

    let x = document.body.appendChildAndReturn html2"<p>Callbacks for XXX.<span>fnord</span></p>"
    check x.nodeName == "P"
    check x.textContent == "Callbacks for modifying text nodes."
    check document.body.childNodes[11] == x

    check x.childNodes[0].nodeName == "#text"
    check x.childNodes[0].textContent == x.textContent

    check len(x.childNodes) == 2
    check x.childNodes[^1].nodeName == "SPAN"
    check x.childNodes[^1].textContent == ""

    let y = document.body.appendChildAndReturn html2"(XXX work even at the top level.)"
    check y.nodeName == "#text"
    check y.textContent == "(modifying text nodes work even at the top level.)"
    check document.body.childNodes[12] == y


  test "can name all nodes on entering":
    macro html2(s: string{lit}): Node =
      let
        code = s.strVal
        context = parseHtml(code).initXom()
        deferred = newStmtList()
      context.onEnter = proc(x: XmlNode): Command =
        EmitNamed
      context.onEmitNamed = proc(node: XmlNode, name: NimNode) =
        if node.kind == xnElement:
          deferred.add quote do:
            `name`.setAttribute("class", "modified")
      result = context
      result.insert len(result) - 1, deferred
      result = avoidNilandPrint(result, code)

    let x = document.body.appendChildAndReturn html2"<p>You can name nodes to be modified later.</p>"
    check x.nodeName == "P"
    check x.textContent == "You can name nodes to be modified later."
    check document.body.childNodes[13] == x

    check x.childNodes[0].nodeName == "#text"
    check x.childNodes[0].textContent == x.textContent

    check len(x.childNodes) == 1
    check x.getAttribute("class") == "modified"


suite "Attribute basics":
  test "can create elements with attributes":
    let x = document.body.appendChildAndReturn html"<p><a href='https://github.com/schneiderfelipe/xom'>Take a look at the project for more.</a></p>"
    check x.nodeName == "P"
    check x.textContent == "Take a look at the project for more."
    check document.body.childNodes[14] == x

    check x.childNodes[0].nodeName == "A"
    check x.childNodes[0].textContent == x.textContent

    check x.childNodes[0].childNodes[0].nodeName == "#text"
    check x.childNodes[0].childNodes[0].textContent == x.textContent

    check x.childNodes[0].getAttribute("href") == "https://github.com/schneiderfelipe/xom"


suite "Real world cases":
  test "can create mean, complex trees":
    let x = document.body.appendChildAndReturn html"""
      <h2>Show case</h2>
      <p>Favorite fruits:</p>
      <ul class='fruits list'>
        <li><a href="https://en.wikipedia.org/wiki/Pineapple"><img src='https://upload.wikimedia.org/wikipedia/commons/thumb/7/74/%E0%B4%95%E0%B5%88%E0%B4%A4%E0%B4%9A%E0%B5%8D%E0%B4%9A%E0%B4%95%E0%B5%8D%E0%B4%95.jpg/320px-%E0%B4%95%E0%B5%88%E0%B4%A4%E0%B4%9A%E0%B5%8D%E0%B4%9A%E0%B4%95%E0%B5%8D%E0%B4%95.jpg' WIDTH=150></a>
        <!-- '&' has to be escaped below, I don't know why: -->
        <li><a href='https://gn.wikipedia.org/wiki/Arasa'><img alt="delicious &amp; tasty!" src='https://upload.wikimedia.org/wikipedia/commons/thumb/0/02/Guava_ID.jpg/320px-Guava_ID.jpg' WIDTH='150' /></a> <emph><STRONG>(most loved!)</STRONG>
        <li><a href=https://pt.wikipedia.org/wiki/Mam%C3%A3o><img WIDTH="150" src=https://upload.wikimedia.org/wikipedia/commons/thumb/4/44/Mam%C3%A3o_papaia_em_fundo_preto.jpg/320px-Mam%C3%A3o_papaia_em_fundo_preto.jpg></a>
      </ul>
    """
    check x.nodeName == "DOCUMENT"
    # check ($x.textContent).filter(c => not isSpaceAscii(c)) == @"ShowcaseFavoritefruits:(mostloved!)"  # TODO: make this work
    check document.body.childNodes[15] == x

    check x.childNodes[0].nodeName == "#text"
    check x.childNodes[0].textContent == " "

    check x.childNodes[1].nodeName == "H2"
    check x.childNodes[1].textContent == "Show case"

    check len(x.childNodes) == 6
    check x.childNodes[^1].nodeName == "UL"
    # check ($x.childNodes[^1].textContent).filter(c => not isSpaceAscii(c)) == @"(mostloved!)"  # TODO: make this work
