(defpackage #:cl-blog/tests
  (:use #:cl #:rove)
  (:local-nicknames (#:blog #:cl-blog)
                    (#:sp #:cl-stack-pathlib)
                    (#:xml #:xml-protocol)
                    (#:dt #:datetime-protocol)))
(in-package #:cl-blog/tests)

(defun nl (&rest lines)
  "LINES joined with #\\Newline, each followed by one."
  (format nil "~{~A~%~}" lines))

(defparameter *site-yaml*
  (nl "title: Test Blog"
      "description: Notes"
      "author: Ada"
      "domain: https://example.org/blog/"
      "per-page: 2"
      "feeds: [lisp]"
      "nav:"
      "  - {name: Home, url: \"https://example.org\"}"
      "license:"
      "  name: CC BY-SA"
      "  url: https://creativecommons.org/licenses/by-sa/4.0/"
      "  image: css/cc.png"))

(defun write-files (root files)
  "FILES: (relative-path . text) written under ROOT."
  (loop for (path . text) in files
        for file = (sp:join root path)
        do (sp:mkdir (sp:parent file))
           (sp:write-text file text)))

(defmacro with-site ((root &rest files) &body body)
  "BODY in a fresh memory filesystem holding ROOT/site.yaml (*SITE-YAML*
unless FILES has one) and FILES."
  `(sp:with-filesystem ((sp:make-memory-filesystem))
     (let ((,root "/site/"))
       (write-files ,root (list* (cons "site.yaml" *site-yaml*) (list ,@files)))
       ,@body)))

(defun out (path)
  "The text of the built file _site/PATH."
  (sp:read-text (sp:join "/site/_site/" path)))

(defun built-p (path)
  (sp:file-p (sp:join "/site/_site/" path)))

(defun has (needle haystack)
  (and (search needle haystack) t))

(defun rfc3339 (moment)
  (dt:print-rfc3339 (dt:zoned-moment-to-instant (dt:moment-in-zone moment dt:+utc+))))
