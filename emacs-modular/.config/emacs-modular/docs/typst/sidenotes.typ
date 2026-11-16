// Sidenotes for see-also notes, with the marginalia package.  Tangled from
// docs/tangles/text/sp-typst.org; edit it there.
//
// Imported by the sp-typst module after template.typ, only for a document
// that has see-also notes.

#import "@preview/marginalia:0.3.1" as marginalia

#let see-also(body) = marginalia.note(body)

#let sidenote-layout(body) = {
  show: marginalia.setup.with(
    inner: (far: 10mm, width: 0mm, sep: 12mm),
    outer: (far: 5mm, width: 45mm, sep: 5mm),
    top: 24mm,
    bottom: 26mm,
    book: false,
  )
  body
}
