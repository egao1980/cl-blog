# cl-blog

"All things Common Lisp": <https://egao1980.github.io/cl-blog/>.

The generator lives in this repo too. It is a small Common Lisp system on the [cl-stack](https://github.com/egao1980/cl-stack): [markdown-protocol](https://github.com/egao1980/markdown-protocol) and [org-markup](https://github.com/egao1980/org-markup) parse posts, [html-markdown](https://github.com/egao1980/html-markdown) and [html-protocol](https://github.com/egao1980/html-protocol) render them, and [engels](https://github.com/egao1980/engels) plus `theme/brutal.lass` (through [css-backend-lass](https://github.com/egao1980/css-backend-lass)) style them. Dependencies come from GHCR through `cl-repo`.

## Writing a post

Add a file to `posts/` named `YYYY-MM-DD-slug.md` or `YYYY-MM-DD-slug.org`. The page is `posts/slug.html`.

```markdown
---
title: A note
date: 2026-11-23 14:05
tags: [lisp, tips]
---

The first paragraph is also the description.

<!--more-->

Everything after the marker is left out of the index page.
```

```org
#+TITLE: A note
#+DATE: <2026-11-23 Mon 14:05>
#+FILETAGS: :lisp:tips:

The first paragraph is also the description.

#+more

Everything after the marker is left out of the index page.
```

| Field | |
|-------|-|
| `title`, `date` | required. `date` is `YYYY-MM-DD`, optionally with `HH:MM[:SS]`, or an org timestamp; read as UTC |
| `tags` | a list or `a, b`; org: `#+FILETAGS: :a:b:` or `#+TAGS: a, b` |
| `slug` | overrides the file name (`YYYY-MM-DD-` dropped) |
| `draft: true` | left out of the build unless `DRAFTS=1` |
| `description` | the meta description; default: the first paragraph |

Without a `<!--more-->` / `#+more` line, the index shows the whole post. URLs in a post are site-root relative: `![x](images/x.png)` is `static/images/x.png`. A link to another post's file (`[see](2026-11-23-other.md)`) goes to that post's page. `javascript:` and similar URLs are dropped.

Full rules: the headers of [`src/post.lisp`](src/post.lisp) (posts), [`src/theme.lisp`](src/theme.lisp) (URLs) and [`src/build.lisp`](src/build.lisp) (pages).

## Building

```sh
bin/build                # → _site/; open _site/index.html (links are relative)
DRAFTS=1 bin/build       # with drafts
cl-repo test             # the generator's tests
```

`site.yaml` holds the title, domain, nav links, licence and extra per-tag feeds. `static/` is copied as is.

## Publishing

`.github/workflows/site.yml` tests and builds every push and PR, and deploys `master` to GitHub Pages (Pages source: GitHub Actions). New posts go through a PR that merges when the build is green. From the cl-workspace, the **blog** skill does this from a note or a conversation.

## Layout

```text
posts/           the posts (.md, .org)
static/          copied into the site (images, the licence badge)
site.yaml        site settings
theme/           brutal.lass, the blog's rules on top of engels
src/             the generator: site, post, theme, feeds, build
tests/           Rove tests (sites built in a memory filesystem)
bin/build        cl-repo run → (cl-blog:build-site)
```

## License

The code is MIT ([LICENSE](LICENSE)). The posts are CC BY-SA 3.0 unless credited otherwise.
