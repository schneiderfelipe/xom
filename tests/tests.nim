import unittest

import xom

import macros, htmlparser, dom


macro html(s: string{lit}): auto =
  ## Helper for HTML parsing.
  parseHtml(s.strVal).createTree()


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
    let x = document.body.appendChildAndReturn html"<div><div>This is xom, a Nim library that converts XmlNodes into DOM calls at compile-time.</div></div>"
    check x.nodeName == "DIV"
    check x.textContent == "This is xom, a Nim library that converts XmlNodes into DOM calls at compile-time."
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
