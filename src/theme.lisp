(in-package #:cl-blog)

;;; ------------------------------------------------------------------
;;; The brutal theme: pages as html-protocol trees, classless semantic
;;; HTML styled by engels + theme/brutal.lass.
;;;
;;; URLs: every link a page makes is relative to that page (REL), so the
;;; built site works from file://, under a project path (/cl-blog/) and at a
;;; domain root. In feeds (*ABSOLUTE-BASE* set) they are absolute.
;;; URLs written in a post or page are site-root relative: "images/a.png"
;;; and "/images/a.png" both mean ROOT/static/images/a.png; a link whose
;;; last segment is another post's (or, on a docs site, page's) source file
;;; name (2026-11-23-note.md, requests.org) goes to that post's or page's
;;; file. Scheme URLs, //host and #fragment links are kept. So are
;;; site.yaml nav URLs with a scheme; other nav URLs are site-root relative.

(defvar *page-path* "index.html"
  "The site-relative path of the page being built.")

(defvar *absolute-base* nil
  "NIL, or \"DOMAIN/\": REL then makes absolute URLs (feeds).")

(defun rel (target)
  "TARGET (site-relative) as a URL from the current page."
  (if *absolute-base*
      (concatenate 'string *absolute-base* target)
      (format nil "~{~A~}~A"
              (make-list (count #\/ *page-path*) :initial-element "../")
              target)))

(defun absolute-url (site path)
  (if (string= path "index.html")
      (format nil "~A/" (site-domain site))
      (format nil "~A/~A" (site-domain site) path)))

;;; Content URLs

(defun %scheme-p (url)
  (let ((colon (position #\: url))
        (slash (position #\/ url)))
    (and colon (plusp colon)
         (or (null slash) (< colon slash))
         (alpha-char-p (char url 0)))))

(defun %url-file-name (url)
  "The last path segment of URL (no query or fragment)."
  (let* ((cut (or (position-if (lambda (ch) (find ch "?#")) url) (length url)))
         (path (subseq url 0 cut)))
    (subseq path (1+ (or (position #\/ path :from-end t) -1)))))

(defun %resolve-content-url (url sources)
  "URL from a post or page, made relative to the current page (see the
header). SOURCES: source file name → its page's site-relative path."
  (if (or (%scheme-p url)
          (and (plusp (length url)) (char= (char url 0) #\#))
          (and (>= (length url) 2) (string= "//" url :end2 2)))
      url
      (let* ((cut (or (position-if (lambda (ch) (find ch "?#")) url) (length url)))
             (site-path (string-left-trim "/" (subseq url 0 cut)))
             (tail (subseq url cut))
             (name (%url-file-name url))
             (target (and (plusp (length name)) (gethash name sources))))
        (concatenate 'string (rel (or target site-path)) tail))))

(defun content-url-fn (sources)
  "The html-markdown URL function for post content on the current page."
  (lambda (url kind)
    (let ((safe (hm:safe-url url kind)))
      (and safe (%resolve-content-url safe sources)))))

(defun %code-language (class)
  "LANG of the first language-LANG word in the CLASS attribute, else NIL."
  (let ((word (find-if (lambda (w) (and (> (length w) 9) (string= "language-" w :end2 9)))
                       (uiop:split-string (or class "") :separator '(#\Space #\Tab)))))
    (and word (subseq word 9))))

(defun %highlight-node (node)
  "Highlight the code blocks in NODE (an html-protocol node), in place."
  (when (html:html-element-p node)
    (if (string-equal (html:html-element-name node) "pre")
        (dolist (code (html:html-element-children node))
          (let ((language (and (html:html-element-p code)
                               (string-equal (html:html-element-name code) "code")
                               (%code-language (html:element-attr code "class")))))
            (when language
              (setf (html:html-element-children code)
                    (hl:highlight-nodes (html:element-text code) language)))))
        (mapc #'%highlight-node (html:html-element-children node)))))

(defun render-content (blocks &rest keys &key heading-offset heading-ids url)
  "BLOCKS (markdown-protocol) as html-protocol nodes with highlighted code:
html-markdown's RENDER-MARKDOWN with KEYS, then the code blocks' spans."
  (declare (ignore heading-offset heading-ids url))
  (let ((nodes (apply #'hm:render-markdown blocks keys)))
    (mapc #'%highlight-node nodes)
    nodes))

;;; Elements

(defun %nodes (children)
  "CHILDREN flattened: strings → text nodes, NIL dropped."
  (loop for c in children
        append (cond ((null c) '())
                     ((stringp c) (list (make-instance 'html:html-text :data c)))
                     ((listp c) (%nodes c))
                     (t (list c)))))

(defun el (name attributes &rest children)
  (html:make-html-element name :attributes attributes :children (%nodes children)))

(defun %a (href &rest children)
  (apply #'el "a" (list (cons "href" href)) children))

(defun %comma-list (items)
  "ITEMS with \", \" between them."
  (loop for (x . more) on items collect x when more collect ", "))

(defun %time (post)
  (el "time" (list (cons "datetime" (post-rfc3339 post))) (post-day post)))

(defun %tag-links (tags)
  "TAGS (names) as links to their pages."
  (%comma-list (mapcar (lambda (name) (%a (rel (format nil "tag/~A.html" (tag-slug name))) name))
                       tags)))

;;; The page

(defun %head (site title description)
  (el "head" nil
      (el "meta" '(("charset" . "utf-8")))
      (el "meta" '(("name" . "viewport") ("content" . "width=device-width, initial-scale=1")))
      (el "title" nil (if title (format nil "~A — ~A" title (site-title site)) (site-title site)))
      (when (plusp (length description))
        (el "meta" (list (cons "name" "description") (cons "content" description))))
      (el "link" (list (cons "rel" "canonical") (cons "href" (absolute-url site *page-path*))))
      (el "link" (list (cons "rel" "stylesheet") (cons "href" (rel "css/style.css"))))
      (when (eq (site-kind site) :blog)
        (list
         (el "link" (list (cons "rel" "alternate") (cons "type" "application/rss+xml")
                          (cons "title" (site-title site)) (cons "href" (rel "rss.xml"))))
         (el "link" (list (cons "rel" "alternate") (cons "type" "application/atom+xml")
                          (cons "title" (site-title site)) (cons "href" (rel "atom.xml"))))))))

(defun %nav-url (url)
  "A site.yaml nav URL: kept when it has a scheme or is //host or #x, else
site-root relative."
  (if (or (%scheme-p url)
          (and (plusp (length url)) (char= (char url 0) #\#))
          (and (>= (length url) 2) (string= "//" url :end2 2)))
      url
      (rel (string-left-trim "/" url))))

(defun %site-header (site)
  (el "header" nil
      (el "nav" nil
          (el "ul" nil
              (loop for (name . url) in (site-nav site)
                    collect (el "li" nil (%a (%nav-url url) name)))))
      (el "h1" nil (%a (rel "index.html") (site-title site)))))

(defun %site-footer (site)
  (let ((license (site-license site)))
    (el "footer" nil
        (el "p" nil
            (if license
                (list "Unless otherwise credited all material "
                      (el "a" (list (cons "rel" "license") (cons "href" (getf license :url)))
                          (if (getf license :image)
                              (el "img" (list (cons "alt" (getf license :name))
                                              (cons "src" (rel (getf license :image)))))
                              (getf license :name)))
                      " by " (site-author site) ". ")
                (list "© " (site-author site) ". "))
            "Built with " (%a "https://github.com/egao1980/cl-blog" "cl-blog")
            " on the " (%a "https://github.com/egao1980/cl-stack" "cl-stack") "."))))

(defun page (site body &key title (description (site-description site)))
  "A full page at *PAGE-PATH* around BODY (nodes for <main>)."
  (html:make-html-document
   :children
   (list (make-instance 'html:html-doctype)
         (el "html" (list (cons "lang" (site-language site)))
             (%head site title description)
             (el "body" nil
                 (%site-header site)
                 (el "main" nil body)
                 (%site-footer site))))))

;;; Post pages

(defun post-page (site post &key older newer sources)
  "POST's page; OLDER / NEWER are its neighbours (or NIL)."
  (let ((*page-path* (post-url post)))
    (page site
          (el "article" nil
              (el "header" nil
                  (el "h1" nil (post-title post))
                  (el "p" nil
                      (when (post-tags post)
                        (list "Tagged as " (%tag-links (post-tags post)) ". "))
                      "Written on " (%time post) "."))
              (render-content (post-blocks post) :heading-offset 1 :heading-ids t
                                                     :url (content-url-fn sources))
              (when (or older newer)
                (el "footer" nil
                    (el "nav" nil
                        (el "ul" nil
                            (when older (el "li" nil (%a (rel (post-url older)) "Previous")))
                            (when newer (el "li" nil (%a (rel (post-url newer)) "Next"))))))))
          :title (post-title post)
          :description (post-description post))))

(defun %heading-level (node)
  "N for an <hN> element node, else NIL."
  (when (html:html-element-p node)
    (let ((name (html:html-element-name node)))
      (and (= 2 (length name))
           (char-equal (char name 0) #\h)
           (digit-char-p (char name 1))))))

(defun %toc-list (entries)
  "ENTRIES ((level text id) …) → a <ul>; an entry deeper than the
shallowest nests in the entry before it."
  (when entries
    (let ((top (reduce #'min entries :key #'first)))
      (el "ul" nil
          (loop while entries
                collect (destructuring-bind (level text id) (pop entries)
                          (declare (ignore level))
                          (let ((children (loop while (and entries (> (first (first entries)) top))
                                                collect (pop entries))))
                            (el "li" nil (%a (format nil "#~A" id) text) (%toc-list children)))))))))

(defun %toc (nodes depth)
  "The contents of a page body (NODES, rendered with heading ids): its
headings from page level 1 (h2) to DEPTH (hDEPTH+1), in a <nav>."
  (let ((entries (loop for node in nodes
                       for level = (%heading-level node)
                       for id = (and level (html:element-attr node "id"))
                       when (and id (<= 2 level (1+ depth)))
                         collect (list level (html:element-text node) id))))
    (when entries
      (el "nav" '(("aria-label" . "Contents"))
          (el "h2" nil "Contents")
          (%toc-list entries)))))

(defun %byline (page)
  (let ((author (page-author page))
        (email (page-email page)))
    (when (or author email)
      (el "p" nil
          (when author (list "By " author))
          (when (and author email) ", ")
          (when email (%a (format nil "mailto:~A" email) email))
          "."))))

(defun %pages-aside (pages current)
  "The other pages but the index, as a list of links."
  (let ((listed (remove-if #'page-index-p pages)))
    (when (and listed (not (page-index-p current)))
      (el "aside" nil
          (el "section" nil
              (el "p" nil "Pages: "
                  (%comma-list (mapcar (lambda (p)
                                         (if (eq p current)
                                             (el "strong" nil (page-title p))
                                             (%a (rel (page-url p)) (page-title p))))
                                       listed))
                  "."))))))

(defun docs-page (site page &key previous next pages sources)
  "PAGE's file (a docs site); PREVIOUS / NEXT are its neighbours in PAGES (or
NIL)."
  (let* ((*page-path* (page-url page))
         (body (render-content (page-blocks page) :heading-offset 1 :heading-ids t
                                                      :url (content-url-fn sources))))
    (page site
          (list
           (el "article" nil
               (el "header" nil
                   (el "h1" nil (page-title page))
                   (%byline page))
               (when (page-toc page) (%toc body (page-toc page)))
               body
               (when (or previous next)
                 (el "footer" nil
                     (el "nav" nil
                         (el "ul" nil
                             (when previous (el "li" nil (%a (rel (page-url previous)) "Previous")))
                             (when next (el "li" nil (%a (rel (page-url next)) "Next"))))))))
           (%pages-aside pages page))
          :title (unless (and (page-index-p page) (string= (page-title page) (site-title site)))
                   (page-title page))
          :description (page-description page))))

;;; List pages (index, tags, months)

(defun %summary-article (post sources)
  (el "article" nil
      (el "header" nil
          (el "h2" nil (%a (rel (post-url post)) (post-title post)))
          (el "p" nil "Posted on " (%time post) "."))
      (render-content (post-excerpt post) :heading-offset 2 :url (content-url-fn sources))
      (when (post-more-p post)
        (el "footer" nil (el "nav" nil (%a (rel (post-url post)) "Continue reading"))))))

(defun %aside (tags months)
  "TAGS: (name . slug); MONTHS: YYYY-MM strings."
  (when (or tags months)
    (el "aside" nil
        (when tags
          (el "section" nil
              (el "p" nil "This blog covers "
                  (%comma-list (loop for (name . slug) in tags
                                     collect (%a (rel (format nil "tag/~A.html" slug)) name)))
                  ".")))
        (when months
          (el "section" nil
              (el "p" nil "View content from "
                  (%comma-list (loop for m in months
                                     collect (%a (rel (format nil "date/~A.html" m)) m)))
                  "."))))))

(defun list-page (site path heading posts &key newer older tags months sources)
  "A page at PATH listing POSTS' excerpts under HEADING. NEWER / OLDER:
site-relative paths of the neighbouring pages, or NIL."
  (let ((*page-path* path))
    (page site
          (list
           (el "header" nil (el "h1" nil heading))
           (mapcar (lambda (p) (%summary-article p sources)) posts)
           (when (or newer older)
             (el "nav" nil
                 (el "ul" nil
                     (when newer (el "li" nil (%a (rel newer) "Newer posts")))
                     (when older (el "li" nil (%a (rel older) "Older posts"))))))
           (%aside tags months))
          :title (unless (string= path "index.html") heading))))

;;; The stylesheet

(defun blog-theme ()
  "The --blog-* colours of theme/brutal.lass, light and dark, plus the
brutal theme's own engels palette (it came after engels' theme, so it wins):
near-black links instead of engels' blue, and the old grey code background."
  (css:make-css-theme :light '(("blog-band" . "#f8f8f8") ("blog-ink" . "#000")
                               ("blog-paper" . "#fff")
                               ("engels-link" . "#101010") ("engels-link-hover" . "#000")
                               ("engels-code-bg" . "#f3f3f3"))
                      :dark '(("blog-band" . "#262a31") ("blog-ink" . "#f3f3f3")
                              ("blog-paper" . "#16181d")
                              ("engels-link" . "#e6e6e6") ("engels-link-hover" . "#fff")
                              ("engels-code-bg" . "#262a31"))
                      :toggle-attribute "data-theme"))

(defun site-stylesheet (&optional documents)
  "engels, the blog colours, highlight-protocol's code colours (light and
dark, the same data-theme toggle) and theme/brutal.lass as one css-protocol
stylesheet; pruned to the rules DOCUMENTS (html-documents) can use."
  (let ((sheet (css:merge-stylesheets
                (engels:stylesheet)
                (css:css-theme-stylesheet (blog-theme))
                (hl:highlight-stylesheet :toggle-attribute "data-theme")
                (css-backend-lass:compile-lass-file
                 (asdf:system-relative-pathname "cl-blog" "theme/brutal.lass")))))
    (if documents
        (css:used-rules sheet (mapcar #'html:document-root documents))
        sheet)))
