# Index rows for pages with no artifact directory

`ARTIFACTS.md` never loses a row, but most of the pages listed there were published before the commit-the-source rule and left nothing on disk to hang a row on. Each file here is one such row: the page's title, URL, org, status, date and one-line summary, in the same schema `artifacts/<slug>/meta.yml` uses.

`scripts/build_artifacts_index.py` reads this directory and every `artifacts/*/meta.yml`, and assembles the table. One row per file is the point — two sessions recording two artifacts write two different files and never conflict.

## What goes here rather than in an artifact directory

- A page whose source was never kept, so there is nothing to put in `artifacts/<slug>/`. `index_source` is `—`, or a note saying where the build went.
- An earlier publication of a page that now lives in an artifact directory — a URL that was superseded, deleted upstream, or published under an org that is no longer reachable. The directory's `meta.yml` describes the current publication; the older URLs get a file here, with `index_source` pointing at the same directory.

A page published from now on gets `artifacts/<slug>/` with its source and built HTML, per `artifacts/README.md`. Nothing new should need a file here.

## Keys

| Key | Required | Content |
|---|---|---|
| `title` | yes | The page title, as the link text |
| `url` | yes | The `https://claude.ai/code/artifact/<uuid>` address, or `unpublished` / `pending-first-publish` before the first publish. Anything else fails the build rather than dropping the row |
| `org` | yes | `orgName` from `claude auth status` at publish time, or `see note` when it was never recorded |
| `status` | yes | One of `live`, `done`, `archived`, `superseded`, `elsewhere` — the builder rejects anything else |
| `status_note` | no | The clause after the status, e.g. `deleted upstream; the URL 404s`. A `superseded` row must link to its replacement here |
| `last_updated` | yes | ISO date of the last publish; the table sorts on it, newest first |
| `summary` | yes | The clause after the em dash in the Artifact cell — what the page established |
| `public` | no | `no` (default), or the public mirror URL |
| `index_source` | no | The Source cell. Defaults to `—` here and to the artifact's own directory in `artifacts/<slug>/meta.yml` |

A literal `|` inside any value would split the row, so write it `\|`; the builder fails rather than emit a broken table.

Each value must have the type its row above describes, and the builder checks the type before it applies any default: a key given a boolean, a number, a list or a mapping fails the build, naming the file, the key, the type and the value. Watch `url`, `public` and `status` in particular — a bare `no`, `off`, `yes` or `on` is a boolean in YAML 1.1, so quote it. Nothing is ever dropped, blanked or defaulted because the builder could not read it.

No key may appear twice in one file. YAML keeps the last value for a repeated key and discards the first without a word, so two `url:` lines would index one address and silently forget the other; the builder names the file, the key and the line instead.

A row here is `<slug>.yml`, one level deep — that path and `artifacts/<slug>/meta.yml` are the only two the builder reads. **Every directory under `artifacts/` is checked against them**: one with no row file in either place is named and the build fails, so a row renamed or moved out of an artifact's directory surfaces as "this artifact has no row" rather than as a table quietly one page short. **The known gap** is the case this directory exists for: a row whose page has no artifact directory has nothing to be missing from, so one meant for `<slug>.yml` here and left at `artifacts/<slug>.yml`, or given another extension, is not detected — it is simply not read, and the published page gets no row. Guessing the answer from the filename was tried twice and defeated both times, so the builder does not guess; put the row here and rebuild the index, which is the check that shows it is being read.
