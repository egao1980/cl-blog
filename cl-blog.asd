(defsystem "cl-blog"
  :version "1.1.0"
  :description "A static blog and docs site generator on the cl-stack: markdown / org posts or pages, the brutal theme on engels, RSS / Atom / sitemap"
  :author "egao1980"
  :license "MIT"
  :depends-on ((:version "markdown-protocol" "0.2.0")
               (:version "org-markup" "0.1.1")
               (:version "html-markdown" "0.1.0")
               (:version "html-protocol" "0.1.1")
               (:version "css-protocol" "0.1.0")
               (:version "css-backend-lass" "0.1.0")
               (:version "engels" "0.2.1")
               (:version "yaml-protocol" "0.2.1")
               "xml-backend-native"
               "datetime-protocol"
               (:version "cl-stack-pathlib" "0.9.0"))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "site")
               (:file "post")
               (:file "page")
               (:file "theme")
               (:file "feeds")
               (:file "build")
               (:static-file "brutal.lass" :pathname "../theme/brutal.lass"))
  :in-order-to ((test-op (test-op "cl-blog/tests"))))

(defsystem "cl-blog/tests"
  :depends-on ("cl-blog" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "post-test")
               (:file "build-test")
               (:file "docs-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
