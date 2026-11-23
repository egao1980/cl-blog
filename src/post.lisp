(in-package #:cl-blog)

;;; ------------------------------------------------------------------
;;; Posts: ROOT/posts/*.md and *.markdown (metadata in YAML front matter
;;; between "---" lines at the top) and *.org (metadata in #+KEY: lines).
;;;
;;;  title        required.
;;;  date         required: YYYY-MM-DD, then optionally HH:MM[:SS] after a
;;;               space or T; an org timestamp <2026-11-23 Mon 14:05> or
;;;               [2026-11-23 Mon] works too. Read as UTC.
;;;  tags         markdown: a YAML list or a comma-separated string; org:
;;;               #+FILETAGS: :a:b: or #+TAGS: a, b.
;;;  slug         the page is posts/SLUG.html. Default: the file name
;;;               without its extension and a leading YYYY-MM-DD-. ASCII
;;;               letters, digits, - _ . only, not starting with a dot.
;;;  draft        true / yes: left out unless BUILD-SITE :drafts t.
;;;  description  the meta description; default: the first paragraph's
;;;               text, cut to about 200 characters.
;;;
;;; Excerpt (index pages): the blocks before a line that is <!--more-->
;;; (markdown) or #+more (org, any case), followed by "Continue reading".
;;; Without that line the excerpt is the whole post. The line itself is
;;; dropped from the post.

(defclass post ()
  ((path :initarg :path :reader post-path :documentation "The source file (a path).")
   (format :initarg :format :reader post-format :documentation ":markdown or :org.")
   (source-name :initarg :source-name :reader post-source-name)
   (slug :initarg :slug :reader post-slug)
   (title :initarg :title :reader post-title)
   (date :initarg :date :reader post-date :documentation "A datetime-protocol MOMENT, UTC.")
   (tags :initarg :tags :reader post-tags :documentation "Tag names, source order.")
   (blocks :initarg :blocks :reader post-blocks)
   (excerpt :initarg :excerpt :reader post-excerpt)
   (more-p :initarg :more-p :reader post-more-p
           :documentation "True when the excerpt is shorter than the post.")
   (draft-p :initarg :draft-p :reader post-draft-p)
   (description :initarg :description :reader post-description))
  (:documentation "A post read by READ-POST: its metadata and its body as
markdown-protocol blocks (org posts too, through org-markup)."))

(defmethod print-object ((post post) stream)
  (print-unreadable-object (post stream :type t)
    (format stream "~A" (post-slug post))))

(defun post-url (post)
  "POST's page, relative to the site root."
  (format nil "posts/~A.html" (post-slug post)))

(defun tag-slug (name)
  "The file name of tag NAME's page (tag/SLUG.html)."
  (hm:heading-slug name))

;;; Dates

(defun parse-post-date (string)
  "STRING (see the header) → a datetime-protocol MOMENT. Signals
DATETIME-PARSE-ERROR."
  (check-type string string)
  (let ((s (string-trim '(#\Space #\Tab #\< #\> #\[ #\]) string)))
    (when (< (length s) 10)
      (error 'dt:datetime-parse-error :input string :message "expected YYYY-MM-DD"))
    (let* ((date (subseq s 0 10))
           (rest (subseq s 10))
           (rest (if (and (plusp (length rest)) (char-equal (char rest 0) #\T))
                     (subseq rest 1)
                     rest))
           (time (find-if (lambda (token) (find #\: token))
                          (uiop:split-string rest :separator '(#\Space #\Tab)))))
      (dt:parse-iso-date date)
      (dt:parse-moment
       (format nil "~AT~A" date
               (cond ((null time) "00:00:00")
                     ((= 1 (count #\: time)) (concatenate 'string time ":00"))
                     (t time)))))))

(defun %instant (moment)
  (dt:zoned-moment-to-instant (dt:moment-in-zone moment dt:+utc+)))

(defun post-rfc3339 (post) (dt:print-rfc3339 (%instant (post-date post))))
(defun post-http-date (post) (dt:print-http-date (%instant (post-date post))))
(defun post-day (post) (dt:print-iso-date (dt:moment-date (post-date post))))
(defun post-month (post) (subseq (post-day post) 0 7))

(defun %newer-p (a b)
  "Newest first; the same date by slug."
  (let ((ka (post-rfc3339 a)) (kb (post-rfc3339 b)))
    (or (string> ka kb)
        (and (string= ka kb) (string< (post-slug a) (post-slug b))))))

;;; Source text

(defun %source-lines (text)
  "TEXT's lines, a byte-order mark and each line's CR dropped."
  (let ((text (if (and (plusp (length text)) (char= (char text 0) (code-char #xFEFF)))
                  (subseq text 1)
                  text)))
    (mapcar (lambda (line) (string-right-trim '(#\Return) line))
            (uiop:split-string text :separator '(#\Newline)))))

(defun %join-lines (lines)
  (format nil "~{~A~^~%~}" lines))

(defun %split-front-matter (lines file)
  "→ (values yaml-text-or-NIL body-lines)."
  (if (and lines (string= (first lines) "---"))
      (let ((end (position-if (lambda (l) (member l '("---" "...") :test #'string=))
                              lines :start 1)))
        (unless end
          (error 'invalid-post :path file :reason "front matter has no closing ---"))
        (values (%join-lines (subseq lines 1 end)) (subseq lines (1+ end))))
      (values nil lines)))

(defun %more-line-p (line format)
  (let ((l (string-trim '(#\Space #\Tab) line)))
    (ecase format
      (:markdown (string= l "<!--more-->"))
      (:org (string-equal l "#+more")))))

(defun %split-more (lines format)
  "→ (values all-lines-without-the-marker excerpt-lines-or-NIL)."
  (let ((i (position-if (lambda (l) (%more-line-p l format)) lines)))
    (if i
        (values (append (subseq lines 0 i) (subseq lines (1+ i))) (subseq lines 0 i))
        (values lines nil))))

;;; Metadata

(defun %meta (meta key)
  "KEY in META: a hash table (YAML front matter) or an alist (org keywords)."
  (cond ((hash-table-p meta)
         (let ((v (gethash key meta))) (if (eq v :null) nil v)))
        (t (cdr (assoc key meta :test #'string-equal)))))

(defun %meta-string (meta key file &key required)
  (let ((v (%meta meta key)))
    (cond ((stringp v) (let ((s (string-trim '(#\Space #\Tab) v)))
                         (if (and required (zerop (length s)))
                             (error 'invalid-post :path file :reason (format nil "~A is empty" key))
                             s)))
          ((realp v) (princ-to-string v))
          ((null v) (when required
                      (error 'invalid-post :path file :reason (format nil "no ~A" key))))
          (t (error 'invalid-post :path file
                    :reason (format nil "~A must be text, not ~S" key v))))))

(defun %split-tags (string separators)
  (remove-if (lambda (s) (zerop (length s)))
             (mapcar (lambda (s) (string-trim '(#\Space #\Tab) s))
                     (uiop:split-string string :separator separators))))

(defun %tags (meta format file)
  (let ((tags
          (ecase format
            (:markdown
             (let ((v (%meta meta "tags")))
               (cond ((null v) '())
                     ((stringp v) (%split-tags v '(#\,)))
                     ((and (vectorp v) (every (lambda (x) (or (stringp x) (realp x))) v))
                      (remove-if (lambda (s) (zerop (length s)))
                                 (map 'list (lambda (x) (string-trim " " (princ-to-string x))) v)))
                     (t (error 'invalid-post :path file
                               :reason "tags must be a list or a comma-separated string")))))
            (:org
             (let ((filetags (%meta meta "filetags"))
                   (tags (%meta meta "tags")))
               (append (and filetags (%split-tags filetags '(#\:)))
                       (and tags (%split-tags tags '(#\, #\Space #\Tab)))))))))
    (remove-duplicates tags :test #'string-equal :from-end t)))

(defun %truthy-p (value)
  (or (eq value t)
      (and (stringp value)
           (member (string-trim " " value) '("t" "true" "yes" "1") :test #'string-equal)
           t)))

(defun %default-slug (stem)
  "STEM without a leading YYYY-MM-DD-."
  (if (and (> (length stem) 11)
           (every #'digit-char-p (concatenate 'string (subseq stem 0 4) (subseq stem 5 7)
                                              (subseq stem 8 10)))
           (char= #\- (char stem 4) (char stem 7) (char stem 10)))
      (subseq stem 11)
      stem))

(defun %valid-slug-p (slug)
  (and (plusp (length slug))
       (char/= (char slug 0) #\.)
       (every (lambda (ch) (or (and (< (char-code ch) 128) (alphanumericp ch)) (find ch "-_.")))
              slug)))

(defun %summary (blocks &optional (limit 200))
  "The first paragraph's text, at most about LIMIT characters."
  (let* ((p (find :paragraph blocks :key (lambda (b) (and (consp b) (first b)))))
         (text (if p (hm:plain-text (second p)) "")))
    (if (<= (length text) limit)
        text
        (let ((cut (or (position #\Space text :end limit :from-end t) limit)))
          (concatenate 'string (string-right-trim " ,.;:" (subseq text 0 cut)) "…")))))

;;; Reading

(defun %post-format (file)
  (let ((ext (string-downcase (sp:extension file))))
    (cond ((member ext '("md" "markdown") :test #'string=) :markdown)
          ((string= ext "org") :org))))

(defun read-post (file)
  "Read the post FILE (a path or path designator) → a POST. Signals
INVALID-POST."
  (let* ((file (sp:ensure-path file))
         (where (sp:as-posix file))
         (format (or (%post-format file)
                     (error 'invalid-post :path where :reason "not .md, .markdown or .org")))
         (lines (%source-lines (sp:read-text file)))
         meta blocks excerpt)
    (ecase format
      (:markdown
       (multiple-value-bind (yaml-text body) (%split-front-matter lines where)
         (setf meta (if yaml-text
                        (handler-case (yaml:decode yaml-text)
                          (yaml:yaml-error (e)
                            (error 'invalid-post :path where
                                                 :reason (format nil "front matter: ~A" e))))
                        (make-hash-table :test 'equal)))
         (unless (hash-table-p meta)
           (error 'invalid-post :path where :reason "front matter must be a mapping"))
         (multiple-value-bind (all before) (%split-more body :markdown)
           (setf blocks (md:parse-markdown (%join-lines all))
                 excerpt (and before (md:parse-markdown (%join-lines before)))))))
      (:org
       (multiple-value-bind (all before) (%split-more lines :org)
         (multiple-value-setq (blocks meta) (org:parse-org (%join-lines all)))
         (setf excerpt (and before (values (org:parse-org (%join-lines before))))))))
    (let* ((title (%meta-string meta "title" where :required t))
           (slug (or (%meta-string meta "slug" where)
                     (%default-slug (pathname-name (sp:path-pathname file)))))
           (date-text (%meta-string meta "date" where :required t))
           (date (handler-case (parse-post-date date-text)
                   (dt:datetime-error ()
                     (error 'invalid-post :path where
                                          :reason (format nil "bad date ~S" date-text))))))
      (unless (%valid-slug-p slug)
        (error 'invalid-post :path where :reason (format nil "bad slug ~S" slug)))
      (make-instance 'post
                     :path file
                     :format format
                     :source-name (sp:name file)
                     :slug slug
                     :title title
                     :date date
                     :tags (%tags meta format where)
                     :blocks blocks
                     :excerpt (or excerpt blocks)
                     :more-p (and excerpt t)
                     :draft-p (%truthy-p (%meta meta "draft"))
                     :description (or (%meta-string meta "description" where)
                                      (%summary blocks))))))

(defun read-posts (site &key drafts)
  "Every post in the site's posts/ directory, newest first; drafts only
when DRAFTS. An unreadable post or a repeated slug signals INVALID-POST
with a CONTINUE restart that leaves the post out."
  (let* ((dir (sp:ensure-directory (sp:join (site-root site) "posts")))
         (files (when (sp:directory-p dir)
                  (sort (loop for pattern in '("*.md" "*.markdown" "*.org")
                              append (sp:glob dir pattern))
                        #'string< :key #'sp:name)))
         (slugs (make-hash-table :test 'equal))
         (posts '()))
    (dolist (file files)
      (restart-case
          (let* ((post (read-post file))
                 (other (gethash (post-slug post) slugs)))
            (when other
              (error 'invalid-post :path (sp:as-posix file)
                                   :reason (format nil "slug ~S is also ~A's" (post-slug post) other)))
            (setf (gethash (post-slug post) slugs) (post-source-name post))
            (when (or drafts (not (post-draft-p post)))
              (push post posts)))
        (continue ()
          :report "Leave this post out."
          nil)))
    (sort posts #'%newer-p)))
