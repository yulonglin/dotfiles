# Anthropic TikZ Style

For full TikZ diagram patterns, see the `tikz-diagrams` skill. This reference covers color/typography integration only.

## Color Definitions

```latex
% Primary
\definecolor{slate}{HTML}{141413}
\definecolor{ivory}{HTML}{FAF9F5}
\definecolor{clay}{HTML}{D97757}

% Secondary
\definecolor{sky}{HTML}{6A9BCC}
\definecolor{olive}{HTML}{788C5D}
\definecolor{fig}{HTML}{C46686}
\definecolor{cactus}{HTML}{BCD1CA}
\definecolor{oat}{HTML}{E3DACC}

% PRETTY_CYCLE (for multi-series)
\definecolor{darkorange}{HTML}{B86046}
\definecolor{grey}{HTML}{656565}
\definecolor{darkblue}{HTML}{40668C}
\definecolor{kraft}{HTML}{D19B75}
\definecolor{lightpurple}{HTML}{8778AB}
\definecolor{darkpurple}{HTML}{4A366F}

% Grayscale
\definecolor{gray700}{HTML}{3D3D3A}
\definecolor{gray400}{HTML}{B0AEA5}
\definecolor{gray200}{HTML}{E8E6DC}
```

## Node Labels

Always label nodes — unlabeled circles are hard to interpret. For neural networks, use subscript notation ($x_1$, $h_1$, $y_1$). For pipelines or flowcharts, use short descriptive text. Layer labels (Input, Hidden, Output) should appear above or below each group.

## Node Style Conventions

```latex
\tikzset{
  anthropic node/.style={
    draw=gray400,
    fill=ivory,
    text=slate,
    rounded corners=4pt,
    inner sep=10pt,
    font=\sffamily,
  },
  accent node/.style={
    anthropic node,
    fill=clay!15,
    draw=clay,
  },
}
```

## Layout Rules

Per `rules/coding-conventions.md`:
- `inner sep >= 10pt`
- `node distance >= 1.5cm`
- Use the `positioning` library, not manual coordinates

### Vertical centering of parallel groups
When drawing multi-layer diagrams (neural networks, pipelines), vertically center each layer so the midpoint aligns across columns. Do NOT let layers cascade/staircase:
```latex
% Center each layer by anchoring its midpoint to a common y-coordinate
\foreach \i in {1,...,4}
  \node[neuron, yshift={(\i-2.5)*1.2cm}] (hidden-\i) at (3,0) {};
% Or use a matrix for automatic centering:
\matrix[column sep=2cm, row sep=0.8cm] {
  % rows auto-center within each column
};
```
The `positioning` library's `below=of` chains nodes top-to-bottom. For centered columns, either compute explicit y-offsets or use `\matrix`.
