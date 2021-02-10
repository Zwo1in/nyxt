;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(in-package :password)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export '*password-store-program*))
(defvar *password-store-program* nil
  "The path to the executable.")
(defconstant +password-store-default-timeout+ 45
  "The default timeout for clipboard reset used by pass.")

(defclass password-store-interface (password-interface)
  ((password-directory :reader password-directory
                       :initarg :directory
                       :initform (or (uiop:getenv "PASSWORD_STORE_DIR")
                                     (namestring (format nil "~a/.password-store"
                                                         (uiop:getenv "HOME")))))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'make-password-store-interface))
(defun make-password-store-interface ()
  (unless *password-store-program*
    (setf *password-store-program* (executable-find "pass")))
  (setf *sleep-timer* (or (uiop:getenv "PASSWORD_STORE_CLIP_TIME")
                          +password-store-default-timeout+))
  (when *password-store-program*
    (make-instance 'password-store-interface)))
(push #'make-password-store-interface interface-list)

(defmethod list-passwords ((password-interface password-store-interface))
  ;; Special care must be taken for symlinks. Say `~/.password-store/work`
  ;; points to `~/work/pass`, would we follow symlinks, we would not be able to
  ;; truncate `~/.password-store/` in `~/work/pass/some/password.gpg`.  Because
  ;; of this, we don't follow symlinks.
  (let ((raw-list (uiop:directory*
                   ;; We truncate the root directory so that the password list
                   ;; resembles the output from `pass list`. To do so, we
                   ;; truncate `~/.password-store/` in the pathname strings of
                   ;; the passwords.
                   (format nil "~a/**/*.gpg"
                           (password-directory password-interface))))
        (dir-length (length (namestring
                             (truename (password-directory password-interface))))))
    (mapcar #'(lambda (x)
                (subseq (namestring x) dir-length (- (length (namestring x)) 4)))
            raw-list)))

(defmethod clip-password ((password-interface password-store-interface) &key password-name service)
  (declare (ignore service))
  (uiop:run-program (list *password-store-program* "show" "--clip" password-name)
                    :output '(:string :stripped t)))

(defmethod save-password ((password-interface password-store-interface)
                          &key password-name password service)
  (declare (ignore service))
  (if (str:emptyp password)
      (uiop:run-program (list *password-store-program* "generate" password-name))
      (with-open-stream (st (make-string-input-stream password))
        (uiop:run-program (list *password-store-program* "insert" "--echo" password-name)
                          :input st))))

(defmethod password-correct-p ((password-interface password-store-interface))
  t)
