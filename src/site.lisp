(in-package #:cl-blog)

;;; site.yaml → SITE. A mapping:
;;;   title, domain, author   strings, required. DOMAIN is the absolute URL
;;;                           the site is served at; a trailing / is dropped.
;;;   description, language   strings ("" and "en" when absent)
;;;   per-page                posts per index page, an integer ≥ 1 (10)
;;;   feeds                   tags that get their own RSS / Atom feeds ([])
;;;   nav                     [{name, url}], the header links ([])
;;;   license                 {name, url, image}: the footer's licence link,
;;;                           IMAGE a path under the site root (none)

(defclass site ()
  ((root :initarg :root :reader site-root
         :documentation "The directory holding site.yaml, posts/ and static/.")
   (title :initarg :title :reader site-title)
   (description :initarg :description :reader site-description)
   (author :initarg :author :reader site-author)
   (domain :initarg :domain :reader site-domain)
   (language :initarg :language :reader site-language)
   (per-page :initarg :per-page :reader site-per-page)
   (feeds :initarg :feeds :reader site-feeds)
   (nav :initarg :nav :reader site-nav :documentation "List of (name . url).")
   (license :initarg :license :reader site-license
            :documentation "NIL or a plist (:name :url :image)."))
  (:documentation "The settings of site.yaml (READ-SITE) and the site root."))

(defun %setting (table key)
  "KEY's value in TABLE; NIL when absent or null."
  (multiple-value-bind (value found) (gethash key table)
    (and found (not (eq value :null)) value)))

(defun %site-string (table key &key required (default ""))
  (let ((value (%setting table key)))
    (cond ((stringp value) (string-trim " " value))
          ((null value)
           (if required
               (error 'invalid-site :reason (format nil "~A is required" key))
               default))
          (t (error 'invalid-site
                    :reason (format nil "~A must be a string, not ~S" key value))))))

(defun %string-list (value what)
  "VALUE (a YAML sequence of strings, NIL or :NULL) → a list of strings."
  (cond ((or (null value) (eq value :null)) '())
        ((and (vectorp value) (not (stringp value)) (every #'stringp value))
         (coerce value 'list))
        (t (error 'invalid-site :reason (format nil "~A must be a list of strings" what)))))

(defun %nav (value)
  (cond ((or (null value) (eq value :null)) '())
        ((and (vectorp value) (not (stringp value)))
         (loop for entry across value
               collect (if (hash-table-p entry)
                           (cons (%site-string entry "name" :required t)
                                 (%site-string entry "url" :required t))
                           (error 'invalid-site :reason "nav entries are {name, url}"))))
        (t (error 'invalid-site :reason "nav must be a list of {name, url}"))))

(defun %license (value)
  (cond ((or (null value) (eq value :null)) nil)
        ((hash-table-p value)
         (list :name (%site-string value "name" :required t)
               :url (%site-string value "url" :required t)
               :image (let ((image (%site-string value "image")))
                        (and (plusp (length image)) image))))
        (t (error 'invalid-site :reason "license must be {name, url, image}"))))

(defun read-site (root)
  "Read ROOT/site.yaml → a SITE. Signals INVALID-SITE."
  (let* ((root (sp:ensure-directory root))
         (file (sp:join root "site.yaml")))
    (unless (sp:file-p file)
      (error 'invalid-site :reason (format nil "no site.yaml in ~A" (sp:as-posix root))))
    (let ((table (handler-case (yaml:decode (sp:read-text file))
                   (yaml:yaml-error (e)
                     (error 'invalid-site :reason (format nil "not YAML: ~A" e))))))
      (unless (hash-table-p table)
        (error 'invalid-site :reason "must be a mapping"))
      (let ((per-page (or (%setting table "per-page") 10)))
        (unless (and (integerp per-page) (plusp per-page))
          (error 'invalid-site :reason "per-page must be a positive integer"))
        (make-instance 'site
                       :root root
                       :title (%site-string table "title" :required t)
                       :description (%site-string table "description")
                       :author (%site-string table "author" :required t)
                       :domain (string-right-trim "/" (%site-string table "domain" :required t))
                       :language (%site-string table "language" :default "en")
                       :per-page per-page
                       :feeds (%string-list (%setting table "feeds") "feeds")
                       :nav (%nav (%setting table "nav"))
                       :license (%license (%setting table "license")))))))
