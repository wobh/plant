#!/usr/bin/guile \
--no-auto-compile -e main -s
!#

(use-modules (ice-9 pretty-print))

(define (curpath p)
  "simply join the path fragment with the current working directory"
  (string-join (list (getcwd) p) "/"))

;; globals

(define *default-quickloads* (list "swank" "alexandria"))
(define *plant-project* (curpath "plant-project.scm"))
(define *plant-dir* (curpath ".plant"))
(define *project-data* '())

(define *quicklisp-url* "http://beta.quicklisp.org/quicklisp.lisp")

;; utilities

(define (path-test op p)
  "wraps the test command."
  (equal? 0 (system (string-join
                     (list "test" op p)))))

(define (file? f)
  "Returns true if 'f' is a valid path to a file."
  (path-test "-f" f))

(define (dir? d)
  "Returns true if 'd' is a valid path to a directory."
  (path-test "-d" d))

(define (project-item item-key)
  (assoc-ref *project-data* item-key))

(define (plant-lisp)
  (project-item #:plant-lisp))

(define (project-name)
  (project-item #:project-name))

(define (project-lisp)
  (format #f ".plant/~a-~a" (plant-lisp) (project-name)))

(define (no-user-init)
  (project-item #:no-user-init))

(define (load-arg arg)
  (string-join (list (project-item #:load) arg)))

(define (eval-arg arg)
  (string-join (list (project-item #:eval) arg)))

(define (save)
  (eval-arg (project-item #:save)))

;; functions

(define (save-project-settings)
  (with-output-to-file *plant-project*
    (lambda ()
      (pretty-print *project-data* (current-output-port)))))

(define (load-project-settings)
  (with-input-from-file *plant-project*
    (lambda ()
      (set! *project-data* (read (current-input-port))))))

(define (install-quicklisp)
  (let ((wget-cmd (string-join (list "wget" *quicklisp-url*)))
        (quicklisp-install-cmd (string-join
                                (list (plant-lisp) (no-user-init)
                                      (load-arg "quicklisp.lisp")
                                      (eval-arg "'(quicklisp-quickstart:install :path #P\"~/.plant/quicklisp/\")'")
                                      (eval-arg "'(quit)'")))))
    (system wget-cmd)
    (system quicklisp-install-cmd)
    (delete-file "quicklisp.lisp")))

(define (build-lisp options)
  (let* ((quickloads (string-join (map (lambda (x) (format #f ":~a" x))
                                       (append *default-quickloads* options))))
         (quickloads-arg (string-join
                          (list "'(ql:quickload '\"'\"'(" quickloads "))'"))))
    (unless (dir? *plant-dir*)
      (mkdir *plant-dir*))
    (system (string-join
             (list (plant-lisp) (no-user-init)
                   (load-arg "~/.plant/quicklisp/setup.lisp")
                   (load-arg "~/.plant/setup.lisp")
                   (eval-arg quickloads-arg)
                   (save))))))

;; commands

(define (help options)
  (format #t "plant init~%")
  (format #t "plant include <git|hg|wget> <url>~%")
  (format #t "plant quickloads <system> [<system> <system> ...]~%")
  (format #t "plant run [--swank [port]]~%")
  (format #t "plant rebuild~%"))

(define (init options)
  (build-lisp options))

(define (quickloads options)
  (if (>= (length options) 1)
      (begin
        (build-lisp options)
        (set! *project-data*
              (assoc-set! *project-data* #:quickloads
                          (append (assoc-ref *project-data* #:quickloads)
                                  options)))
        (save-project-settings))
      (help options)))

(define (run options)
  (let* ((option-count (length options))
         (swank? (equal? "--swank" (when (>= option-count 1)
                                       (car options))))
         (default-port "4005")
         (port (if (>= option-count 2)
                   (cadr options)
                   default-port))
         (swank-arg-template "'(swank:create-server :dont-close t :port ~a)'")
         (swank-args (eval-arg (format #f swank-arg-template port)))
         (cmd-line (string-join (list (project-lisp)
                                      (no-user-init)
                                      (if swank?
                                          swank-args
                                          "")))))
    (if (file? (curpath (project-lisp)))
        (system cmd-line)
        (begin
          (format #t "ERROR: The current directory does not appear to be a plant project.~%~a~%~a~%"
                  (project-lisp) (cmd-line))
          (exit 2)))))

(define (rebuild options) #f)

(define (include options) #f)

;; entry point

(define (main args)
  "There isn't much here. We just take the command and the options and run."

  ;; we need at least a command
  (when (< (length args) 2)
    (help '())
    (exit 255))

  (if (not (file? *plant-project*))
      ;; load the default configurations for supported lisps
      ;; and initialize the project data
      (begin
        (format #t "Unable to locate a project file (~a) creating a new one.~%" *plant-project*)
        (let* ((plant-lisp-bin (or (getenv "PLANT_LISP") "sbcl"))
               (project-defaults-file (format #f "~a/.plant/~a-defaults.scm"
                                              (getenv "HOME") (if (or (equal? plant-lisp-bin "ccl")
                                                                      (equal? plant-lisp-bin "ccl64"))
                                                                  "clozure"
                                                                  plant-lisp-bin)))
               (project-name (basename (getcwd))))
          ;; If there is no defaults file for the current lisp then we bail
          (unless (file? project-defaults-file)
            (help '())
            (format #t "ERROR: ~a is not currently supported by plant.~%" plant-lisp-bin)
            (exit 2))
          ;; Load the defaults and add/update values for the current project
          (set! *project-data* (with-input-from-file project-defaults-file
                                 (lambda () (read (current-input-port)))))
          (set! *project-data* (assoc-set! *project-data* #:project-name project-name))
          (set! *project-data* (assoc-set! *project-data* #:plant-lisp plant-lisp-bin))
          (set! *project-data* (assoc-set! *project-data* #:quickloads *default-quickloads*))
          (set! *project-data* (assoc-set! *project-data* #:save
                                           (format #f (assoc-ref *project-data* #:save)
                                                   (project-lisp)))))
        (save-project-settings))
      ;; else load the existing project data and bind it
      (load-project-settings))

  (unless (dir? (string-join (list (getenv "HOME") ".plant" "quicklisp") "/"))
    (install-quicklisp))

  (unless (defined? '*project-data*)
    (format #t "ERROR: Unable to load or create project data!")
    (exit 3))
  
  (let* ((command (cadr args))
         (options (cddr args)))
    ;; dispatch further work to the individual command handlers
    (cond ((equal? command "run") (run options))
          ((equal? command "quickloads") (quickloads options))
          ((equal? command "update") (rebuild options))
          ((equal? command "include") (include options))
          ((equal? command "init") (init options))
          ((equal? command "help") (help options))
          (#t (help options)))))
