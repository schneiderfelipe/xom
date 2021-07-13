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


suite "Basics":
  test "can create text nodes":
    let x = document.body.appendChildAndReturn html"Hello, world!"
    check x.nodeName == "#text"
    check x.textContent == "Hello, world!"
    check document.body.childNodes[2] == x

  test "can create empty elements":
    let x = document.body.appendChildAndReturn html"<h1></h1>"
    check x.nodeName == "H1"
    check x.textContent == ""
    check document.body.childNodes[3] == x

  test "can create elements containing text":
    let x = document.body.appendChildAndReturn html"<h1>Hello, world!</h1>"
    check x.nodeName == "H1"
    check x.textContent == "Hello, world!"
    check document.body.childNodes[4] == x

  test "can create elements containing distinct elements":
    let x = document.body.appendChildAndReturn html"<h1><a>Hello, world!</a></h1>"
    check x.nodeName == "H1"
    check x.textContent == "Hello, world!"
    check document.body.childNodes[5] == x

    check x.childNodes[0].nodeName == "A"
    check x.childNodes[0].textContent == "Hello, world!"

  test "can create elements containing similar elements":
    let x = document.body.appendChildAndReturn html"<div><div>Hello, world!</div></div>"
    check x.nodeName == "DIV"
    check x.textContent == "Hello, world!"
    check document.body.childNodes[6] == x

    check x.childNodes[0].nodeName == "DIV"
    check x.childNodes[0].textContent == "Hello, world!"