// Template of the PDF of the literate docs.  Tangled from
// docs/tangles/text/sp-typst.org; edit it there.
//
// Loaded by `#import "template.typ": book` and `#show: book`, which the
// sp-typst module writes at the top of every file it exports.

#let accent = rgb("#3a6ea5")
#let body-font = "Libertinus Serif"
#let mono-font = "DejaVu Sans Mono"

#let book(body) = {
  set page(
    paper: "a4",
    margin: (x: 22mm, top: 24mm, bottom: 26mm),
    footer: context {
      let n = counter(page).get().first()
      if n > 1 {
        set text(size: 8pt, fill: luma(110))
        align(center, [#n])
      }
    },
  )
  set text(font: body-font, size: 10.5pt)
  set par(justify: true, leading: 0.62em)
  set outline(depth: 2)

  // Parts start a page; so does every doc.
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    v(1.2em)
    text(size: 22pt, fill: accent, weight: "bold", it)
    v(0.8em)
  }
  show heading.where(level: 2): it => {
    pagebreak(weak: true)
    text(size: 15pt, fill: accent, weight: "bold", it)
    v(0.4em)
  }
  show heading.where(level: 3): set text(size: 12pt)
  show heading: set block(above: 1.3em, below: 0.7em)

  show outline.entry.where(level: 1): set text(weight: "bold")

  // Code.  Source blocks arrive as a figure around a raw block.
  show raw: set text(font: mono-font, size: 7.8pt)
  show raw.where(block: true): it => block(
    width: 100%,
    fill: luma(247),
    stroke: 0.4pt + luma(215),
    radius: 2pt,
    inset: 7pt,
    breakable: true,
    it,
  )
  show raw.where(block: false): box.with(
    fill: luma(240),
    inset: (x: 2pt),
    outset: (y: 2.5pt),
    radius: 1.5pt,
  )
  show figure.where(kind: raw): set block(breakable: true)
  show figure.where(kind: raw): set align(left)

  show quote.where(block: true): set block(inset: (left: 1em))
  show link: set text(fill: accent)
  set table(stroke: 0.4pt + luma(190), inset: 5pt)

  // Title page.
  context {
    align(center + horizon)[
      #text(size: 28pt, weight: "bold", fill: accent, document.title)
      #v(1.2em)
      #text(size: 13pt, document.author.join(", "))
      #v(0.6em)
      #text(size: 10pt, fill: luma(110), datetime.today().display("[year]-[month]-[day]"))
    ]
  }
  pagebreak()

  body
}
