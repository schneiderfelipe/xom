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
