# ToC Diagram — Move divider line right to clear O4 box

## Context

After the previous O2/O3/O4 spacing fix, O4's right edge lands at ~15.96cm (x=12.8 + 2.6cm text + 0.56cm padding), which extends past the vertical divider at x=15.6. The line renders under the Publication card.

## Change

`toc-diagram.tex` line 36 — shift divider x from 15.6 → 16.1:

```latex
% Before
\draw[medgray, line width=0.8pt] (15.6, 0.3) -- (15.6, 16.2);
% After
\draw[medgray, line width=0.8pt] (16.1, 0.3) -- (16.1, 16.2);
```

## Verification

- `pdflatex toc-diagram.tex` compiles
- Visual: divider line sits in the gap between O4 and the Outcomes column, not under any card
