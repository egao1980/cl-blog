(in-package #:cl-blog)

;;; ------------------------------------------------------------------
;;; The site:
;;;   index.html, 1.html … N.html  newest posts' excerpts, PER-PAGE each
;;;                                (index.html = 1.html, canonical /)
;;;   posts/SLUG.html              a post
;;;   tag/SLUG.html, date/YYYY-MM.html   the posts of a tag / month
;;;   rss.xml, atom.xml            the newest 20 posts
;;;   tag/SLUG-rss.xml, tag/SLUG-atom.xml   for each tag in site.yaml feeds
;;;   sitemap.xml, css/style.css   (engels + brutal, pruned to the pages)
;;;   static/…                     copied as is

(defparameter +feed-size+ 20)

(defun %chunks (list size)
  (loop while list
        collect (loop repeat size while list collect (pop list))))

(defun %tag-index (posts)
  "→ list of (name slug . posts), by name; POSTS newest first."
  (let ((table (make-hash-table :test 'equal))
        (order '()))
    (dolist (post posts)
      (dolist (name (post-tags post))
        (let* ((slug (tag-slug name))
               (entry (gethash slug table)))
          (unless entry
            (setf entry (list name slug)
                  (gethash slug table) entry)
            (push entry order))
          (setf (cddr entry) (append (cddr entry) (list post))))))
    (sort order #'string-lessp :key #'first)))

(defun %month-index (posts)
  "→ list of (YYYY-MM . posts), newest month first."
  (let ((months '()))
    (dolist (post posts)
      (let* ((m (post-month post))
             (entry (assoc m months :test #'string=)))
        (if entry
            (setf (cdr entry) (append (cdr entry) (list post)))
            (push (list m post) months))))
    (sort months #'string> :key #'first)))

(defun render-site (site &key drafts)
  "SITE's generated files → a list of (site-relative-path . text), static/
not included."
  (let* ((posts (read-posts site :drafts drafts))
         (sources (let ((h (make-hash-table :test 'equal)))
                    (dolist (p posts h) (setf (gethash (post-source-name p) h) p))))
         (tags (%tag-index posts))
         (months (%month-index posts))
         (tag-links (mapcar (lambda (e) (cons (first e) (second e))) tags))
         (month-names (mapcar #'first months))
         (documents '())
         (sitemap '()))
    (flet ((add (path document &optional lastmod)
             (push (cons path document) documents)
             (push (cons path lastmod) sitemap)))
      ;; posts
      (loop with v = (coerce posts 'vector)
            for i from 0 below (length v)
            for post = (aref v i)
            do (add (post-url post)
                    (post-page site post
                               :newer (and (> i 0) (aref v (1- i)))
                               :older (and (< (1+ i) (length v)) (aref v (1+ i)))
                               :sources sources)
                    (post-day post)))
      ;; numbered index pages
      (let* ((pages (or (%chunks posts (site-per-page site)) (list '())))
             (n (length pages)))
        (loop for chunk in pages
              for k from 1
              for path = (format nil "~D.html" k)
              for lastmod = (and chunk (post-day (first chunk)))
              do (flet ((index-page (at)
                          (list-page site at "Recent posts" chunk
                                     :newer (cond ((= k 1) nil)
                                                  ((= k 2) "index.html")
                                                  (t (format nil "~D.html" (1- k))))
                                     :older (and (< k n) (format nil "~D.html" (1+ k)))
                                     :tags tag-links :months month-names :sources sources)))
                   (when (= k 1) (add "index.html" (index-page "index.html") lastmod))
                   (add path (index-page path) lastmod))))
      ;; tags and months
      (loop for (name slug . tagged) in tags
            for path = (format nil "tag/~A.html" slug)
            do (add path (list-page site path (format nil "Content tagged ~A" name) tagged
                                    :tags tag-links :months month-names :sources sources)
                    (post-day (first tagged))))
      (loop for (month . dated) in months
            for path = (format nil "date/~A.html" month)
            do (add path (list-page site path (format nil "Content from ~A" month) dated
                                    :tags tag-links :months month-names :sources sources)
                    (post-day (first dated)))))
    (let* ((documents (nreverse documents))
           (feed-posts (subseq posts 0 (min +feed-size+ (length posts))))
           (files
             (append
              (mapcar (lambda (d) (cons (car d) (html:serialize (cdr d)))) documents)
              (list (cons "css/style.css"
                          (css:write-stylesheet (site-stylesheet (mapcar #'cdr documents))
                                                :pretty nil))
                    (cons "rss.xml" (rss-feed site feed-posts "rss.xml" :sources sources))
                    (cons "atom.xml" (atom-feed site feed-posts "atom.xml" :sources sources)))
              (loop for name in (site-feeds site)
                    for slug = (tag-slug name)
                    for tagged = (cddr (find slug tags :key #'second :test #'string=))
                    for title = (format nil "~A: ~A" (site-title site) name)
                    for rss = (format nil "tag/~A-rss.xml" slug)
                    for atom = (format nil "tag/~A-atom.xml" slug)
                    for some = (subseq tagged 0 (min +feed-size+ (length tagged)))
                    collect (cons rss (rss-feed site some rss :title title :sources sources))
                    collect (cons atom (atom-feed site some atom :title title :sources sources))))))
      (append files (list (cons "sitemap.xml" (sitemap site (nreverse sitemap))))))))

(defun %check-output (root output)
  "Signal UNSAFE-OUTPUT unless OUTPUT is a directory strictly inside ROOT."
  (let ((rel (handler-case (sp:as-posix (sp:relative-to output root))
               (sp:not-relative-error () nil))))
    (when (or (null rel) (member (string-right-trim "/" rel) '("" ".") :test #'string=)
              (search ".." rel))
      (error 'unsafe-output :path (sp:as-posix output)))))

(defun build-site (&key (root (sp:cwd)) output drafts)
  "Build the site in ROOT (default: the current directory) into OUTPUT
(default ROOT/_site/, which must be inside ROOT): delete OUTPUT, copy
ROOT/static/ into it, then write every generated file. DRAFTS includes
draft posts. → the number of files written, so a build script can end
with (uiop:quit (if (cl-blog:build-site) 0 1)).
Signals INVALID-SITE, INVALID-POST (CONTINUE leaves the post out) and
UNSAFE-OUTPUT."
  (let* ((site (read-site root))
         (root (site-root site))
         (out (sp:ensure-directory (or output (sp:join root "_site")))))
    (%check-output root out)
    (let ((files (render-site site :drafts drafts))
          (static (sp:ensure-directory (sp:join root "static"))))
      (sp:rmtree out :missing-ok t)
      (sp:mkdir out)
      (when (sp:directory-p static)
        (sp:copytree static out :exist-ok t))
      (loop for (path . text) in files
            for file = (sp:join out path)
            do (sp:mkdir (sp:parent file))
               (sp:write-text file text))
      (length files))))
