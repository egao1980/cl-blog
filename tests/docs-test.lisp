(in-package #:cl-blog/tests)

(defparameter *docs-yaml*
  (nl "title: Docs"
      "author: Ada"
      "domain: https://example.org/docs/"
      "kind: docs"
      "pages-dir: \".\""
      "index: alternatives.org"
      "exclude: [README.md]"
      "nav:"
      "  - {name: Index, url: index.html}"
      "  - {name: Code, url: \"https://github.com/x/y\"}"))

(defparameter *pages*
  (list (cons "site.yaml" *docs-yaml*)
        (cons "alternatives.org"
              (nl "#+TITLE: All alternatives"
                  "#+AUTHOR: Ada"
                  "#+EMAIL: ada@example.org"
                  "#+OPTIONS: author:t email:t toc:t"
                  "* Popular"
                  ":PROPERTIES:"
                  ":UNNUMBERED: t"
                  ":END:"
                  "- [[file+emacs:requests.org][Requests]] (#8)"
                  "- [[file:json.org][json]]"
                  "** HTTP"
                  "Text."))
        (cons "requests.org"
              (nl "#+TITLE: Requests"
                  "#+AUTHOR: Ada"
                  "#+EMAIL: ada@example.org"
                  "#+OPTIONS: author:t email:t toc:t"
                  "#+PROPERTY: header-args:lisp :session *lisp* :exports both"
                  ""
                  "#+name: shorten"
                  "#+BEGIN_SRC emacs-lisp :var result=\"\" :exports none :results silent"
                  "(s-truncate 120 result)"
                  "#+END_SRC"
                  ""
                  "* Requests"
                  ":PROPERTIES:"
                  ":UNNUMBERED: t"
                  ":END:"
                  "| Library | Verdict |"
                  "|---------+---------|"
                  "| Dexador | Mature  |"
                  "** Examples"
                  "See [[file:json.org][json]]."
                  "#+begin_src lisp"
                  "(+ 1 2)"
                  "#+end_src"
                  ""
                  "#+RESULTS:"
                  ": 3"))
        (cons "json.org" (nl "#+TITLE: json" "#+AUTHOR: Ada" "#+EMAIL: ada@example.org"
                             "" "* json" "Parse it."))
        (cons "notes.md" (nl "---" "title: Notes" "toc: true" "author: Bob" "---"
                             "Back to [the index](alternatives.org)."
                             "# First" "## Second" "Text."))
        (cons "README.md" "Not a page: no front matter.")
        (cons "static/images/x.png" "png")))

(deftest docs-build-writes-pages
  (with-site (root)
    (write-files root *pages*)
    (ok (plusp (blog:build-site :root root)))
    (dolist (path '("index.html" "requests.html" "json.html" "notes.html"
                    "css/style.css" "sitemap.xml" "images/x.png"))
      (ok (built-p path) path))
    (dolist (path '("alternatives.html" "readme.html" "README.html" "rss.xml" "atom.xml"
                    "1.html" "tag/lisp.html"))
      (ng (built-p path) (format nil "no ~A" path)))))

(deftest docs-pages
  (with-site (root)
    (write-files root *pages*)
    (blog:build-site :root root)
    (let ((index (out "index.html"))
          (requests (out "requests.html"))
          (json (out "json.html"))
          (notes (out "notes.html"))
          (sitemap (out "sitemap.xml")))
      (ok (has "<title>All alternatives — Docs</title>" index))
      (ok (has "<h1>All alternatives</h1>" index))
      (ok (has "href=\"requests.html\">Requests</a> (#8)" index) "file+emacs: link → the page")
      (ok (has "href=\"json.html\">json</a>" index) "file: link → the page")
      (ok (has "By Ada, <a href=\"mailto:ada@example.org\">ada@example.org</a>." index)
          "author and, with email:t, the e-mail")
      (ok (has "<nav aria-label=\"Contents\"><h2>Contents</h2><ul><li><a href=\"#popular\">Popular</a><ul><li><a href=\"#http\">HTTP</a>"
               index)
          "toc:t: nested contents")
      (ng (has "rss.xml" index) "no feeds")
      (ng (has "Pages:" index) "the index has no page list")
      (ok (has "href=\"requests.html\">Next</a>" index) "index → the first page it links")
      (ng (has "s-truncate" requests) ":exports none helper dropped")
      (ng (has "UNNUMBERED" requests) "property drawers hidden")
      (ok (has "<pre><code class=\"language-lisp\">(+ 1 2)" requests) "a src block with its language")
      (ok (has "<pre><code>3" requests) ":exports both from header-args: the result")
      (ok (has "<th>Library</th>" requests) "tables")
      (ok (has "href=\"json.html\">json</a>" requests))
      (ok (has "href=\"index.html\">Previous</a>" requests))
      (ok (has "href=\"json.html\">Next</a>" requests) "then the next page the index links")
      (ok (has "Pages: <strong>Requests</strong>, <a href=\"json.html\">json</a>, <a href=\"notes.html\">Notes</a>." requests)
          "the page list: linked order, then by title")
      (ok (has "<a href=\"index.html\">Index</a>" requests) "a site-relative nav URL")
      (ok (has "<a href=\"https://github.com/x/y\">Code</a>" requests))
      (ok (has "<p>By Ada.</p>" json) "email:nil is Org's default")
      (ng (has "Contents" json) "no toc unless asked for")
      (ok (has "By Bob." notes) "markdown author")
      (ok (has "href=\"index.html\">the index</a>" notes) "a link to the index page's source")
      (ok (has "<a href=\"#first\">First</a><ul><li><a href=\"#second\">Second</a>" notes)
          "markdown toc: true")
      (ng (has "Next</a>" notes) "the last page")
      (ok (has "<loc>https://example.org/docs/</loc>" sitemap))
      (ok (has "<loc>https://example.org/docs/requests.html</loc>" sitemap))
      (ok (xml:decode sitemap) "sitemap.xml is well-formed XML"))))

(deftest docs-read-pages
  (with-site (root)
    (write-files root *pages*)
    (let* ((site (blog:read-site root))
           (pages (blog:read-pages site)))
      (ok (eq :docs (blog:site-kind site)))
      (ok (equal '("alternatives" "requests" "json" "notes") (mapcar #'blog:page-slug pages)))
      (ok (blog:page-index-p (first pages)))
      (ok (equal '("index.html" "requests.html") (mapcar #'blog:page-url (subseq pages 0 2))))
      (ok (eql 3 (blog:page-toc (first pages))) "toc:t → 3 levels")
      (ok (null (blog:page-toc (third pages))))
      (ok (null (blog:page-email (third pages))))
      (ok (equal "Ada" (blog:page-author (third pages)))))))

(deftest docs-errors
  (with-site (root (cons "site.yaml" (nl "title: D" "author: A" "domain: https://x.y" "kind: wiki")))
    (ok (signals (blog:read-site root) 'blog:invalid-site) "an unknown kind"))
  (with-site (root (cons "site.yaml" (nl "title: D" "author: A" "domain: https://x.y"
                                         "kind: docs" "pages-dir: ../up")))
    (ok (signals (blog:read-site root) 'blog:invalid-site) "pages-dir outside the site"))
  (with-site (root (cons "site.yaml" (nl "title: D" "author: A" "domain: https://x.y"
                                         "kind: docs" "index: missing.org"))
                   (cons "pages/a.org" (nl "#+TITLE: A")))
    (ok (signals (blog:build-site :root root) 'blog:invalid-site) "an index that is no page"))
  (with-site (root (cons "site.yaml" (nl "title: D" "author: A" "domain: https://x.y" "kind: docs"))
                   (cons "pages/a.org" (nl "#+TITLE: A")))
    (ok (signals (blog:build-site :root root) 'blog:invalid-site) "no index page"))
  (with-site (root (cons "site.yaml" (nl "title: D" "author: A" "domain: https://x.y" "kind: docs"))
                   (cons "pages/index.md" (nl "---" "title: Home" "---" "Hi."))
                   (cons "pages/untitled.org" (nl "* no title"))
                   (cons "pages/a.org" (nl "#+TITLE: A" "#+SLUG: b"))
                   (cons "pages/b.md" (nl "---" "title: B" "---")))
    (ok (signals (blog:build-site :root root) 'blog:invalid-page) "no title, or one URL twice")
    (let ((skipped '()))
      (handler-bind ((blog:invalid-page (lambda (c)
                                          (push (blog:invalid-page-path c) skipped)
                                          (continue c))))
        (blog:build-site :root root))
      (ok (equal '("/site/pages/b.md" "/site/pages/untitled.org") (sort skipped #'string<))
          "CONTINUE leaves both pages out")
      (ok (built-p "index.html") "index.md is the default index page")
      (ok (built-p "b.html") "a.org (slug b) claims b.html first")
      (ng (built-p "a.html"))
      (ng (built-p "untitled.html")))))

(deftest blog-nav-urls
  (with-site (root (cons "site.yaml" (nl "title: B" "author: A" "domain: https://x.y"
                                         "nav:" "  - {name: About, url: about.html}"
                                         "  - {name: Feed, url: /rss.xml}"))
                   (cons "posts/2026-01-01-a.md" (nl "---" "title: A" "date: 2026-01-01" "---" "x")))
    (blog:build-site :root root)
    (ok (has "href=\"../about.html\">About</a>" (out "posts/a.html")) "site-relative from a post")
    (ok (has "href=\"rss.xml\">Feed</a>" (out "index.html")))
    (ok (has "application/rss+xml" (out "index.html")) "blogs keep their feed links")))
