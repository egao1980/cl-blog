(in-package #:cl-blog)

(define-condition blog-error (error) ()
  (:documentation "Base of the errors cl-blog signals."))

(define-condition invalid-site (blog-error)
  ((reason :initarg :reason :reader invalid-site-reason))
  (:report (lambda (c s) (format s "site.yaml: ~A" (invalid-site-reason c))))
  (:documentation "site.yaml is missing or a required setting is wrong."))

(define-condition invalid-post (blog-error)
  ((path :initarg :path :reader invalid-post-path)
   (reason :initarg :reason :reader invalid-post-reason))
  (:report (lambda (c s)
             (format s "~A: ~A" (invalid-post-path c) (invalid-post-reason c))))
  (:documentation "A post cannot be read: no title, a bad date or slug, a
slug another post has. READ-POSTS offers CONTINUE (leave the post out)."))

(define-condition invalid-page (blog-error)
  ((path :initarg :path :reader invalid-page-path)
   (reason :initarg :reason :reader invalid-page-reason))
  (:report (lambda (c s)
             (format s "~A: ~A" (invalid-page-path c) (invalid-page-reason c))))
  (:documentation "A docs page cannot be read: no title, a bad slug, a slug
another page has. READ-PAGES offers CONTINUE (leave the page out)."))

(define-condition unsafe-output (blog-error)
  ((path :initarg :path :reader unsafe-output-path))
  (:report (lambda (c s)
             (format s "Refusing to replace ~A: the output directory must be ~
                        inside the site root and not the root itself"
                     (unsafe-output-path c))))
  (:documentation "BUILD-SITE would delete the site (or something above it)."))
