(defpackage #:cl-blog
  (:use #:cl)
  (:local-nicknames (#:sp #:cl-stack-pathlib)
                    (#:md #:markdown-protocol)
                    (#:org #:org-markup)
                    (#:hm #:html-markdown)
                    (#:hl #:highlight-protocol)
                    (#:html #:html-protocol)
                    (#:css #:css-protocol)
                    (#:xml #:xml-protocol)
                    (#:dt #:datetime-protocol)
                    (#:yaml #:yaml-protocol))
  (:export
   ;; conditions
   #:blog-error #:invalid-site #:invalid-site-reason
   #:invalid-post #:invalid-post-path #:invalid-post-reason
   #:invalid-page #:invalid-page-path #:invalid-page-reason
   #:unsafe-output #:unsafe-output-path
   ;; site
   #:site #:read-site #:site-root #:site-kind #:site-title #:site-description #:site-author
   #:site-domain #:site-language #:site-per-page #:site-feeds #:site-nav #:site-license
   #:site-pages-dir #:site-index #:site-exclude
   ;; posts
   #:post #:read-post #:read-posts #:parse-post-date
   #:post-path #:post-format #:post-slug #:post-title #:post-date #:post-tags
   #:post-blocks #:post-excerpt #:post-more-p #:post-draft-p #:post-description
   #:post-url #:tag-slug
   ;; docs pages
   #:page #:read-page #:read-pages
   #:page-path #:page-format #:page-source-name #:page-slug #:page-title #:page-blocks
   #:page-description #:page-author #:page-email #:page-toc #:page-index-p #:page-url
   ;; building
   #:render-site #:build-site #:site-stylesheet #:render-content))
