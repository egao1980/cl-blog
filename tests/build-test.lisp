(in-package #:cl-blog/tests)

(defparameter *posts*
  (list (cons "posts/2026-01-10-older.md"
              (nl "---" "title: Older post" "date: 2026-01-10 08:00" "tags: [lisp]" "---"
                  "See ![a diagram](images/d.png) and [the newer one](2026-02-20-newer.md#top)."
                  "<!--more-->"
                  "# Details"
                  "Code: `(car x)`."))
        (cons "posts/2026-02-20-newer.md"
              (nl "---" "title: Newer <post>" "date: 2026-02-20" "tags: [lisp, web]" "---"
                  "Body with [a link](https://example.com) and [bad](javascript:alert(1))."))
        (cons "posts/2026-02-25-an-org-note.org"
              (nl "#+TITLE: An org note" "#+DATE: [2026-02-25 Wed]" "#+FILETAGS: :org:"
                  "" "Written in *Org*."))
        (cons "posts/2026-03-01-draft.md"
              (nl "---" "title: Draft" "date: 2026-03-01" "draft: true" "---" "Not yet."))
        (cons "static/images/d.png" "png")
        (cons "static/css/cc.png" "png")))

(deftest build-writes-the-site
  (with-site (root)
    (write-files root *posts*)
    (let ((n (blog:build-site :root root)))
      (ok (and (integerp n) (plusp n)) "the number of files written")
      (dolist (path '("index.html" "1.html" "2.html" "posts/older.html" "posts/newer.html"
                      "posts/an-org-note.html" "tag/lisp.html" "tag/web.html" "tag/org.html"
                      "date/2026-01.html" "date/2026-02.html" "rss.xml" "atom.xml"
                      "tag/lisp-rss.xml" "tag/lisp-atom.xml" "sitemap.xml" "css/style.css"
                      "images/d.png" "css/cc.png"))
        (ok (built-p path) path))
      (ng (built-p "posts/draft.html") "drafts left out")
      (ng (built-p "3.html") "per-page 2: two index pages for three posts"))))

(deftest build-pages
  (with-site (root)
    (write-files root *posts*)
    (blog:build-site :root root)
    (let ((index (out "index.html"))
          (older (out "posts/older.html"))
          (newer (out "posts/newer.html"))
          (org (out "posts/an-org-note.html")))
      (ok (has "<!DOCTYPE html><html lang=\"en\">" index))
      (ok (has "<title>Test Blog</title>" index) "index title: the site's")
      (ok (has "href=\"css/style.css\"" index) "relative stylesheet at the root")
      (ok (has "<link rel=\"canonical\" href=\"https://example.org/blog/\">" index))
      (ok (has "An org note" index))
      (ok (has "Newer &lt;post&gt;" index) "titles escaped")
      (ng (has "Older post" index) "page 1 holds the newest two")
      (ok (has "href=\"2.html\">Older posts" index))
      (ok (has "href=\"index.html\">Newer posts" (out "2.html")))
      (ok (has "Continue reading" (out "2.html")) "an excerpt with <!--more-->")
      (ok (has "src=\"images/d.png\"" (out "2.html")) "content URLs relative to the index page")
      (ok (has "<title>Older post — Test Blog</title>" older))
      (ok (has "href=\"../css/style.css\"" older) "relative stylesheet one level down")
      (ok (has "src=\"../images/d.png\" alt=\"a diagram\"" older) "image under static/")
      (ok (has "href=\"../posts/newer.html#top\"" older) "a link to another post's source file")
      (ok (has "<h2 id=\"details\">Details</h2>" older) "post headings shifted, with ids")
      (ok (has "<time datetime=\"2026-01-10T08:00:00Z\">2026-01-10</time>" older))
      (ok (has "href=\"../tag/lisp.html\">lisp</a>" older))
      (ok (has "href=\"../posts/newer.html\">Next</a>" older) "Next: the newer neighbour")
      (ok (has "href=\"../posts/newer.html\">Previous</a>" org) "Previous: the older neighbour")
      (ng (has "Previous" older) "the oldest post has no previous")
      (ok (has "<a href=\"https://example.com\">a link</a>" newer))
      (ok (has "and bad." newer) "javascript: link dropped to its text")
      (ok (has "<strong>Org</strong>" org) "org posts render")
      (ok (has "src=\"../css/cc.png\"" older) "licence image")
      (ok (has "Content tagged lisp" (out "tag/lisp.html")))
      (ok (has "Content from 2026-02" (out "date/2026-02.html"))))))

(deftest build-feeds-and-css
  (with-site (root)
    (write-files root *posts*)
    (blog:build-site :root root)
    (let ((rss (xml:decode (out "rss.xml")))
          (atom (out "atom.xml"))
          (sitemap (out "sitemap.xml"))
          (css (out "css/style.css")))
      (ok rss "rss.xml is well-formed XML")
      (ok (xml:decode atom) "atom.xml is well-formed XML")
      (ok (xml:decode sitemap) "sitemap.xml is well-formed XML")
      (ok (= 3 (count-matches "<item>" (out "rss.xml"))) "every published post")
      (ok (has "<pubDate>Fri, 20 Feb 2026 00:00:00 GMT</pubDate>" (out "rss.xml")))
      (ok (has "https://example.org/blog/images/d.png" (out "rss.xml")) "absolute URLs in feeds")
      (ok (has "<feed xmlns=\"http://www.w3.org/2005/Atom\">" atom))
      (ok (has "<id>https://example.org/blog/posts/older.html</id>" atom))
      (ok (= 2 (count-matches "<item>" (out "tag/lisp-rss.xml"))) "the lisp tag feed")
      (ok (has "<loc>https://example.org/blog/posts/newer.html</loc>" sitemap))
      (ok (has "<loc>https://example.org/blog/</loc>" sitemap))
      (ok (has "--blog-band" css) "the blog colours")
      (ok (has "--engels-" css) "engels underneath"))))

(defun count-matches (needle haystack)
  (loop with start = 0
        for i = (search needle haystack :start2 start)
        while i count t do (setf start (1+ i))))

(deftest build-output-safety
  (with-site (root)
    (ok (signals (blog:build-site :root root :output root) 'blog:unsafe-output) "the root itself")
    (ok (signals (blog:build-site :root root :output "/elsewhere/") 'blog:unsafe-output) "outside")
    (ok (signals (blog:build-site :root root :output "/site/../x/") 'blog:unsafe-output) "..")
    (ok (plusp (blog:build-site :root root :output "/site/public/")) "inside: fine")
    (ok (sp:file-p "/site/public/index.html")))
  (with-site (root)
    (write-files root (list (cons "_site/stale.html" "old")))
    (blog:build-site :root root)
    (ng (built-p "stale.html") "the output is replaced")
    (ok (built-p "index.html") "an empty site still has an index")))
