(in-package #:cl-blog)

;;; ------------------------------------------------------------------
;;; Docs pages (site.yaml kind: docs): the *.md, *.markdown and *.org files
;;; directly in PAGES-DIR, except the EXCLUDE names and dot files. The
;;; metadata is read as in posts (YAML front matter, #+KEY: lines):
;;;
;;;  title        required.
;;;  slug         the page is SLUG.html at the site root. Default: the file
;;;               name without its extension. The index page is index.html
;;;               whatever its slug. A post slug's characters only.
;;;  description  the meta description; default: the first paragraph.
;;;  author       shown under the title. Org: #+AUTHOR, unless #+OPTIONS
;;;               has author:nil (Org's default is author:t).
;;;  email        a mailto: link after the author. Org: #+EMAIL, only with
;;;               #+OPTIONS email:t (Org's default is email:nil).
;;;  toc          a table of contents of the page's headings down to that
;;;               level: markdown toc: true (3) or a number; org #+OPTIONS
;;;               toc:t (then H:N, else 3) or toc:N. Off unless asked for
;;;               (Org's default is on).
;;; Dates, tags, drafts and excerpts are post things: pages have none.
;;; Org source blocks follow org-markup's babel :exports rules.
;;;
;;; Order (Previous / Next and the page list): the index page, then the
;;; pages in the order the index page first links to them, then the rest by
;;; title. A link whose last segment is a page's source file name
;;; (requests.org, [[file:requests.org]], [[file+emacs:requests.org]]) goes
;;; to that page.

(defclass page ()
  ((path :initarg :path :reader page-path :documentation "The source file (a path).")
   (format :initarg :format :reader page-format :documentation ":markdown or :org.")
   (source-name :initarg :source-name :reader page-source-name)
   (slug :initarg :slug :reader page-slug)
   (title :initarg :title :reader page-title)
   (blocks :initarg :blocks :reader page-blocks)
   (description :initarg :description :reader page-description)
   (author :initarg :author :reader page-author :documentation "Shown, or NIL.")
   (email :initarg :email :reader page-email :documentation "Shown, or NIL.")
   (toc :initarg :toc :reader page-toc
        :documentation "NIL, or the deepest heading level of the contents.")
   (index-p :initarg :index-p :initform nil :accessor page-index-p
            :documentation "True for the index page (READ-PAGES sets it)."))
  (:documentation "A docs page read by READ-PAGE: its metadata and its body
as markdown-protocol blocks (org pages too, through org-markup)."))

(defmethod print-object ((page page) stream)
  (print-unreadable-object (page stream :type t)
    (format stream "~A" (page-slug page))))

(defun page-url (page)
  "PAGE's file, relative to the site root: index.html for the index page."
  (if (page-index-p page)
      "index.html"
      (format nil "~A.html" (page-slug page))))

(defun %nonempty (string)
  (and string (plusp (length string)) string))

(defun %toc-depth (value file)
  "A markdown page's toc value → NIL or a depth."
  (cond ((null value) nil)
        ((eq value t) 3)
        ((and (integerp value) (plusp value)) value)
        ((and (integerp value) (zerop value)) nil)
        (t (error 'invalid-page :path file :reason "toc must be true, false or a number"))))

(defun %org-page-meta (keywords file)
  "→ (values author email toc) of an org page's KEYWORDS (see the header)."
  (let ((options (org:org-options keywords)))
    (flet ((option (name default)
             (let ((cell (assoc name options :test #'string=)))
               (if cell (cdr cell) default)))
           (text (key)
             (%nonempty (%meta-string keywords key file :condition 'invalid-page))))
      (let ((toc (option "toc" nil))
            (levels (option "H" 3)))
        (values (and (option "author" t) (text "author"))
                (and (option "email" nil) (text "email"))
                (cond ((and (integerp toc) (plusp toc)) toc)
                      ((eq toc t) (if (and (integerp levels) (plusp levels)) levels 3))))))))

(defun read-page (file)
  "Read the page FILE (a path or path designator) → a PAGE. Signals
INVALID-PAGE."
  (let* ((file (sp:ensure-path file))
         (where (sp:as-posix file))
         (format (or (%post-format file)
                     (error 'invalid-page :path where :reason "not .md, .markdown or .org")))
         (lines (%source-lines (sp:read-text file)))
         meta blocks author email toc)
    (ecase format
      (:markdown
       (multiple-value-bind (yaml-text body) (%split-front-matter lines where 'invalid-page)
         (setf meta (if yaml-text
                        (handler-case (yaml:decode yaml-text)
                          (yaml:yaml-error (e)
                            (error 'invalid-page :path where
                                                 :reason (format nil "front matter: ~A" e))))
                        (make-hash-table :test 'equal)))
         (unless (hash-table-p meta)
           (error 'invalid-page :path where :reason "front matter must be a mapping"))
         (setf blocks (md:parse-markdown (%join-lines body))
               author (%nonempty (%meta-string meta "author" where :condition 'invalid-page))
               email (%nonempty (%meta-string meta "email" where :condition 'invalid-page))
               toc (%toc-depth (%meta meta "toc") where))))
      (:org
       (multiple-value-setq (blocks meta) (org:parse-org (%join-lines lines)))
       (multiple-value-setq (author email toc) (%org-page-meta meta where))))
    (let ((title (%meta-string meta "title" where :required t :condition 'invalid-page))
          (slug (or (%nonempty (%meta-string meta "slug" where :condition 'invalid-page))
                    (pathname-name (sp:path-pathname file)))))
      (unless (%valid-slug-p slug)
        (error 'invalid-page :path where :reason (format nil "bad slug ~S" slug)))
      (make-instance 'page
                     :path file
                     :format format
                     :source-name (sp:name file)
                     :slug slug
                     :title title
                     :blocks blocks
                     :description (or (%nonempty (%meta-string meta "description" where
                                                               :condition 'invalid-page))
                                      (%summary blocks))
                     :author author
                     :email email
                     :toc toc))))

;;; Order

(defun %link-urls (tree)
  "The URLs of the (:link url …) nodes in TREE (blocks or inlines), in
document order."
  (let ((urls '()))
    (labels ((walk (x)
               (when (consp x)
                 (if (and (eq (first x) :link) (stringp (second x)))
                     (progn (push (second x) urls)
                            (walk (cddr x)))
                     (mapc #'walk x)))))
      (walk tree))
    (nreverse urls)))

(defun %order-pages (index others)
  "INDEX (or NIL) first, then OTHERS in the order INDEX first links to them,
then the rest by title."
  (let ((by-name (make-hash-table :test 'equal))
        (linked '()))
    (dolist (p others)
      (setf (gethash (page-source-name p) by-name) p))
    (when index
      (dolist (url (%link-urls (page-blocks index)))
        (let ((p (and (not (%scheme-p url)) (gethash (%url-file-name url) by-name))))
          (when (and p (not (member p linked)))
            (push p linked)))))
    (setf linked (nreverse linked))
    (append (and index (list index))
            linked
            (sort (remove-if (lambda (p) (member p linked)) others)
                  #'string-lessp :key #'page-title))))

(defun %page-files (site)
  "The page source files of SITE, by name."
  (let ((dir (sp:ensure-directory (sp:join (site-root site) (site-pages-dir site)))))
    (when (sp:directory-p dir)
      (sort (remove-if (lambda (file)
                         (let ((name (sp:name file)))
                           (or (char= (char name 0) #\.)
                               (member name (site-exclude site) :test #'string=))))
                       (loop for pattern in '("*.md" "*.markdown" "*.org")
                             append (sp:glob dir pattern)))
            #'string< :key #'sp:name))))

(defun read-pages (site)
  "Every page of the docs SITE, in order (see the header), the index page
first with PAGE-INDEX-P true. The index page is the site's INDEX file, else
index.org, else index.md; there may be none. An unreadable page or two
pages with one URL signal INVALID-PAGE with a CONTINUE restart that leaves
the page out. An INDEX naming no page file signals INVALID-SITE."
  (let* ((files (%page-files site))
         (names (mapcar #'sp:name files))
         (index-name (cond ((site-index site)
                            (or (find (site-index site) names :test #'string=)
                                (error 'invalid-site
                                       :reason (format nil "index ~A is not a page in ~A"
                                                       (site-index site) (site-pages-dir site)))))
                           ((find "index.org" names :test #'string=))
                           ((find "index.md" names :test #'string=))))
         (urls (make-hash-table :test 'equal))
         (pages '()))
    (dolist (file files)
      (restart-case
          (let ((page (read-page file)))
            (when (equal (page-source-name page) index-name)
              (setf (page-index-p page) t))
            (let ((other (gethash (page-url page) urls)))
              (when other
                (error 'invalid-page :path (sp:as-posix file)
                                     :reason (format nil "~A is also ~A's page"
                                                     (page-url page) other))))
            (setf (gethash (page-url page) urls) (page-source-name page))
            (push page pages))
        (continue ()
          :report "Leave this page out."
          nil)))
    (let ((index (find-if #'page-index-p pages)))
      (%order-pages index (remove index (nreverse pages))))))
