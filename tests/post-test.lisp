(in-package #:cl-blog/tests)

(deftest post-dates
  (ok (equal "2020-04-14T15:09:43Z" (rfc3339 (blog:parse-post-date "2020-04-14 15:09:43"))))
  (ok (equal "2026-11-23T00:00:00Z" (rfc3339 (blog:parse-post-date "2026-11-23"))) "date only")
  (ok (equal "2026-11-23T14:05:00Z" (rfc3339 (blog:parse-post-date "2026-11-23T14:05"))) "HH:MM")
  (ok (equal "2026-11-23T14:05:00Z" (rfc3339 (blog:parse-post-date "<2026-11-23 Mon 14:05>")))
      "org active timestamp")
  (ok (equal "2026-11-24T00:00:00Z" (rfc3339 (blog:parse-post-date "[2026-11-24 Tue]")))
      "org inactive timestamp, weekday starting with T")
  (ok (signals (blog:parse-post-date "23/11/2026") 'dt:datetime-parse-error))
  (ok (signals (blog:parse-post-date "2026") 'dt:datetime-parse-error)))

(deftest markdown-posts
  (with-site (root (cons "posts/2026-11-23-first-note.md"
                         (nl "---"
                             "title: \"First: a note\""
                             "date: 2026-11-23 10:00:00"
                             "tags: [lisp, Notes]"
                             "---"
                             ""
                             "Intro *text*."
                             "<!--more-->"
                             "# Rest"
                             "More.")))
    (let ((post (blog:read-post (sp:join root "posts/2026-11-23-first-note.md"))))
      (ok (equal "First: a note" (blog:post-title post)))
      (ok (equal "first-note" (blog:post-slug post)) "slug: the file name without the date")
      (ok (equal '("lisp" "Notes") (blog:post-tags post)))
      (ok (eq :markdown (blog:post-format post)))
      (ok (equal '((:paragraph ("Intro " (:emph ("text")) "."))
                   (:heading 1 ("Rest"))
                   (:paragraph ("More.")))
                 (blog:post-blocks post))
          "the <!--more--> line is dropped")
      (ok (equal '((:paragraph ("Intro " (:emph ("text")) "."))) (blog:post-excerpt post)))
      (ok (blog:post-more-p post))
      (ok (equal "Intro text." (blog:post-description post)) "description: the first paragraph")
      (ng (blog:post-draft-p post))))
  (with-site (root (cons "posts/x.md"
                         (nl "---" "title: X" "date: 2026-01-01" "tags: a, b ,, c"
                             "slug: Custom-Slug" "draft: true" "description: Given." "---" "Body.")))
    (let ((post (blog:read-post (sp:join root "posts/x.md"))))
      (ok (equal '("a" "b" "c") (blog:post-tags post)) "comma-separated tags")
      (ok (equal "Custom-Slug" (blog:post-slug post)))
      (ok (blog:post-draft-p post))
      (ok (equal "Given." (blog:post-description post)))
      (ng (blog:post-more-p post) "no separator: the excerpt is the post")
      (ok (equal (blog:post-blocks post) (blog:post-excerpt post))))))

(deftest org-posts
  (with-site (root (cons "posts/2026-11-23-org-note.org"
                         (nl "#+TITLE: An org note"
                             "#+DATE: <2026-11-23 Mon 09:30>"
                             "#+FILETAGS: :lisp:org:"
                             ""
                             "Some /italic/ text."
                             "#+more"
                             "* Heading"
                             "#+BEGIN_SRC lisp"
                             "(+ 1 2)"
                             "#+END_SRC")))
    (let ((post (blog:read-post (sp:join root "posts/2026-11-23-org-note.org"))))
      (ok (equal "An org note" (blog:post-title post)))
      (ok (equal "org-note" (blog:post-slug post)))
      (ok (equal "2026-11-23T09:30:00Z" (rfc3339 (blog:post-date post))))
      (ok (equal '("lisp" "org") (blog:post-tags post)) "FILETAGS")
      (ok (eq :org (blog:post-format post)))
      (ok (equal '((:paragraph ("Some " (:emph ("italic")) " text."))
                   (:heading 1 ("Heading"))
                   (:code-block "lisp" ("(+ 1 2)")))
                 (blog:post-blocks post)))
      (ok (equal '((:paragraph ("Some " (:emph ("italic")) " text."))) (blog:post-excerpt post))
          "#+more splits the excerpt")
      (ok (blog:post-more-p post)))))

(deftest invalid-posts
  (flet ((bad (text)
           (with-site (root (cons "posts/p.md" text))
             (handler-case (progn (blog:read-post (sp:join root "posts/p.md")) nil)
               (blog:invalid-post (c) (blog:invalid-post-reason c))))))
    (ok (has "no title" (bad (nl "---" "date: 2026-01-01" "---" "x"))))
    (ok (has "no date" (bad (nl "---" "title: T" "---" "x"))))
    (ok (has "bad date" (bad (nl "---" "title: T" "date: soon" "---" "x"))))
    (ok (has "bad slug" (bad (nl "---" "title: T" "date: 2026-01-01" "slug: a/b" "---" "x"))))
    (ok (has "bad slug" (bad (nl "---" "title: T" "date: 2026-01-01" "slug: .hidden" "---" "x"))))
    (ok (has "no closing" (bad (nl "---" "title: T" "date: 2026-01-01" "x"))))
    (ok (has "mapping" (bad (nl "---" "- a list" "---" "x"))))
    (ok (has "no title" (bad "No front matter at all.")))))

(deftest reading-all-posts
  (with-site (root (cons "posts/2026-01-01-a.md" (nl "---" "title: A" "date: 2026-01-01" "---" "a"))
                   (cons "posts/2026-02-01-b.md" (nl "---" "title: B" "date: 2026-02-01" "---" "b"))
                   (cons "posts/2026-03-01-c.md"
                         (nl "---" "title: C" "date: 2026-03-01" "draft: yes" "---" "c"))
                   (cons "posts/2026-04-01-dup.md"
                         (nl "---" "title: Dup" "date: 2026-04-01" "slug: a" "---" "d"))
                   (cons "posts/notes.txt" "not a post"))
    (let ((site (blog:read-site root)))
      (ok (signals (blog:read-posts site) 'blog:invalid-post) "a repeated slug")
      (let ((posts (handler-bind ((blog:invalid-post #'continue))
                     (blog:read-posts site))))
        (ok (equal '("b" "a") (mapcar #'blog:post-slug posts))
            "CONTINUE leaves the later duplicate out; drafts out; newest first"))
      (let ((posts (handler-bind ((blog:invalid-post #'continue))
                     (blog:read-posts site :drafts t))))
        (ok (equal '("c" "b" "a") (mapcar #'blog:post-slug posts)) ":drafts t")))))

(deftest site-settings
  (with-site (root)
    (let ((site (blog:read-site root)))
      (ok (equal "Test Blog" (blog:site-title site)))
      (ok (equal "https://example.org/blog" (blog:site-domain site)) "trailing / dropped")
      (ok (= 2 (blog:site-per-page site)))
      (ok (equal '("lisp") (blog:site-feeds site)))
      (ok (equal '(("Home" . "https://example.org")) (blog:site-nav site)))
      (ok (equal "css/cc.png" (getf (blog:site-license site) :image)))))
  (flet ((bad (yaml)
           (with-site (root (cons "site.yaml" yaml))
             (handler-case (progn (blog:read-site root) nil)
               (blog:invalid-site (c) (blog:invalid-site-reason c))))))
    (ok (has "title is required" (bad (nl "author: A" "domain: https://x"))))
    (ok (has "per-page" (bad (nl "title: T" "author: A" "domain: https://x" "per-page: 0"))))
    (ok (has "nav" (bad (nl "title: T" "author: A" "domain: https://x" "nav: 3"))))
    (ok (has "mapping" (bad "- a")))))
