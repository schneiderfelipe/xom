![hello.nim](examples/hello/hello.png)

# xom

Transform XML trees into JavaScript DOM calls at compile-time using Nim.

The above code will create code similar to the following:

```javascript
var p0 = document.createElement("p");
p0.appendChild(document.createTextNode("Hello!"));
document.body.appendChild(p0);
```

This library produces Nim code that compiles to performant JavaScript DOM
calls.

## Customizing code generation

xom can be customized to generate code that is optimized for a particular use
case. You can modify nodes in-place, suppress code generation for certain
nodes, force creation of referencing variables to certain nodes, and more.

This customization of the behavior is performed by the use of two callbacks:
- `onEnter(node: XmlNode): Command`
- `onEmitCode(node: XmlNode, name: string = ""): Command`

`onEnter` is called when a new node is found, and `onEmitCode` when code
for a node is emitted (i.e., with `createElement` or `createTextNode` and
eventually `setAttribute` and `appendChild`).
Inside callbacks, you can modify nodes as much as you want.

`Command` is an enum with the following values:
- `Discard`: discard the node and its children and don't emit any code.
- `Emit`: emit code to create the node (default behavior).
- `EmitNamed`: emit code to create the node, and also create a variable for
it.

**Note**: `EmitNamed` can only be (meaningfully) returned from `onEnter`:
returning `EmitNamed` from `onEmitCode` means the same as `Emit`, since the
decision to create a variable has already been made at that point.

The default implementation of both `onEnter` and `onEmitCode` is as follows:

```nim
proc(_: XmlNode, _: string = "") =
  Emit
```

By default, no variables are created at the toplevel (xom avoids creating
variables and, if really needed, they are scoped by default).
You can force a node to have a variable at the toplevel of the generated code
by returning `EmitNamed` from `onEnter`.
Furthermore, contigous text nodes are automatically merged unless they are
forced to be referenced by a variable.

When `onEmitCode` is called, `name` is either empty or the name of an
automatically generated variable in the emitted code.
You can use `name` to refer to the node in custom emitted code (for example,
to dynamically modify the node at runtime).
