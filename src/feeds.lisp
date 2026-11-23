(in-package #:cl-blog)

;;; RSS 2.0, Atom 1.0 and sitemap.xml, built as xml-protocol nodes. Entry
;;; content is the post's full HTML with absolute URLs.

(defparameter +atom-ns+ "http://www.w3.org/2005/Atom")
(defparameter +sitemap-ns+ "http://www.sitemaps.org/schemas/sitemap/0.9")

(defun %x (name attributes &rest children)
  (apply #'xml:make-xml-element name attributes (remove nil children)))

(defun post-content-html (site post sources)
  "POST's body as an HTML string with absolute URLs."
  (let ((*absolute-base* (format nil "~A/" (site-domain site))))
    (hm:markdown-html (post-blocks post) :heading-offset 1
                                         :url (content-url-fn sources))))

(defun %encode (root)
  (xml:encode (xml:make-xml-document :children (list root)) :pretty t))

(defun rss-feed (site posts path &key (title (site-title site)) sources)
  "RSS 2.0 for POSTS (newest first), served at PATH."
  (%encode
   (%x "rss" '(("version" . "2.0"))
       (apply #'%x "channel" nil
              (%x "title" nil title)
              (%x "link" nil (absolute-url site "index.html"))
              (%x "atom:link" (list (cons "xmlns:atom" +atom-ns+)
                                    (cons "href" (absolute-url site path))
                                    (cons "rel" "self")
                                    (cons "type" "application/rss+xml")))
              (%x "description" nil (if (plusp (length (site-description site)))
                                        (site-description site)
                                        title))
              (%x "language" nil (site-language site))
              (when posts (%x "lastBuildDate" nil (post-http-date (first posts))))
              (loop for post in posts
                    for url = (absolute-url site (post-url post))
                    collect (apply #'%x "item" nil
                                   (%x "title" nil (post-title post))
                                   (%x "link" nil url)
                                   (%x "guid" '(("isPermaLink" . "true")) url)
                                   (%x "pubDate" nil (post-http-date post))
                                   (%x "description" nil (post-content-html site post sources))
                                   (mapcar (lambda (tag) (%x "category" nil tag))
                                           (post-tags post))))))))

(defun atom-feed (site posts path &key (title (site-title site)) sources)
  "Atom 1.0 for POSTS (newest first), served at PATH."
  (%encode
   (apply #'%x "feed" (list (cons "xmlns" +atom-ns+))
          (%x "title" nil title)
          (%x "link" (list (cons "href" (absolute-url site "index.html"))))
          (%x "link" (list (cons "rel" "self") (cons "href" (absolute-url site path))))
          (%x "id" nil (absolute-url site path))
          (%x "updated" nil (if posts (post-rfc3339 (first posts)) "1970-01-01T00:00:00Z"))
          (%x "author" nil (%x "name" nil (site-author site)))
          (loop for post in posts
                for url = (absolute-url site (post-url post))
                collect (apply #'%x "entry" nil
                               (%x "title" nil (post-title post))
                               (%x "link" (list (cons "href" url)))
                               (%x "id" nil url)
                               (%x "published" nil (post-rfc3339 post))
                               (%x "updated" nil (post-rfc3339 post))
                               (%x "content" '(("type" . "html"))
                                   (post-content-html site post sources))
                               (mapcar (lambda (tag) (%x "category" (list (cons "term" tag))))
                                       (post-tags post)))))))

(defun sitemap (site entries)
  "ENTRIES: (path . lastmod-YYYY-MM-DD-or-NIL)."
  (%encode
   (apply #'%x "urlset" (list (cons "xmlns" +sitemap-ns+))
          (loop for (path . lastmod) in entries
                collect (%x "url" nil
                            (%x "loc" nil (absolute-url site path))
                            (when lastmod (%x "lastmod" nil lastmod)))))))
