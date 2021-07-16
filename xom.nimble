# Package

version       = "0.1.0"
author        = "Felipe S. S. Schneider"
description   = "Transform XML trees into DOM calls at compile-time in Nim."
license       = "MIT"
srcDir        = "src"
backend       = "js"

# Dependencies

requires "nim >= 1.2.6"

# Tasks

task docs, "Generate documentation":
  exec "nim doc --project --index:on --git.url:https://github.com/schneiderfelipe/xom --git.commit:master --outdir:docs src/xom.nim"
  exec "ln -s xom.html docs/index.html || true"
