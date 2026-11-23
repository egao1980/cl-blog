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

Full rules: the headers of [`src/post.lisp`](src/post.lisp) (posts), [`src/page.lisp`](src/page.lisp) (docs pages), [`src/theme.lisp`](src/theme.lisp) (URLs) and [`src/build.lisp`](src/build.lisp) (the files a site has).

## Building

```sh
bin/build                # → _site/; open _site/index.html (links are relative)
DRAFTS=1 bin/build       # with drafts
cl-repo test             # the generator's tests
```

`site.yaml` holds the title, domain, nav links, licence and extra per-tag feeds. `static/` is copied as is. Nav URLs without a scheme (`about.html`) are site-root relative.

## Docs sites

`kind: docs` in `site.yaml` builds a set of pages instead of a blog: no dates, tags, feeds or numbered index pages. [python-to-cl](https://github.com/egao1980/python-to-cl) is one.

```yaml
kind: docs
title: Common Lisp alternatives to popular Python packages
author: Nikolai Matiushev
domain: https://egao1980.github.io/python-to-cl
pages-dir: "."              # the pages' directory (default: pages)
index: alternatives.org     # the page that is index.html (default: index.org, else index.md)
exclude: [README.md]        # files in pages-dir that are not pages
nav:
  - {name: Index, url: index.html}
```

Every `.org`, `.md` and `.markdown` file directly in `pages-dir` is a page at `SLUG.html` (the file name without its extension; `slug` / `#+SLUG` overrides it). A page needs a title (`#+TITLE` / `title`). Org pages show `#+AUTHOR` unless `#+OPTIONS` has `author:nil`, `#+EMAIL` with `email:t`, and a table of contents with `toc:t` or `toc:N`; markdown pages use `author`, `email` and `toc: true` in front matter. Source blocks follow org-babel's `:exports` (`none` hides a helper block, `both` shows its `#+RESULTS:`). Pages link to each other by file name: `[[file:requests.org][Requests]]` goes to `requests.html`. Previous / Next and the page list follow the order the index page links the pages in.

Another repo builds its site with cl-blog from GHCR: a `qlfile` with `ql cl-blog`, then `cl-repo run -- sbcl … --eval '(asdf:load-system "cl-blog")' --eval '(cl-blog:build-site)'` (python-to-cl's `bin/build` and `.github/workflows/site.yml`).

## Publishing

`.github/workflows/site.yml` tests and builds every push and PR, and deploys `master` to GitHub Pages (Pages source: GitHub Actions). The generator itself is published to `ghcr.io/egao1980/cl-systems/cl-blog` by `publish-checkout.yml` (run it after a version bump: `gh workflow run publish-checkout.yml -R egao1980/cl-blog`). New posts go through a PR that merges when the build is green. From the cl-workspace, the **blog** skill does this from a note or a conversation.

## Layout

```text
posts/           the posts (.md, .org)
static/          copied into the site (images, the licence badge)
site.yaml        site settings
theme/           brutal.lass, the blog's rules on top of engels
src/             the generator: site, post, page, theme, feeds, build
tests/           Rove tests (sites built in a memory filesystem)
bin/build        cl-repo run → (cl-blog:build-site)
```

## License

The code is MIT ([LICENSE](LICENSE)). The posts are CC BY-SA 3.0 unless credited otherwise.
