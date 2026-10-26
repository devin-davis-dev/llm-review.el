;;; llm-review-test.el --- Tests for llm-review.el -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Devin Davis

;;; Commentary:

;; ERT test suite for `llm-review.el'.

;;; Code:

(require 'ert)
(require 'llm-review)

(defconst llm-review-test--test-dir
  (file-name-as-directory (expand-file-name "test-sandbox" default-directory))
  "Directory used for temporary files during tests.")

(defun llm-review-test--setup ()
  "Create test directory and dummy source files."
  (make-directory llm-review-test--test-dir t)
  (let ((src-file (expand-file-name "sample.py" llm-review-test--test-dir)))
    (with-temp-file src-file
      (insert "# Line 1: Header\n"
              "def unused_func_one():\n"      ; line 2
              "    x = 1\n"                   ; line 3
              "    return x\n"                ; line 4
              "\n"                            ; line 5
              "def preserved_func():\n"       ; line 6
              "    return 42\n"               ; line 7
              "\n"                            ; line 8
              "def unused_func_two():\n"      ; line 9
              "    pass\n"                    ; line 10
              "\n"                            ; line 11
              "# Line 12: Footer\n"))))

(defun llm-review-test--teardown ()
  "Clean up test artifacts and buffers."
  (when (get-buffer llm-review-buffer-name)
    (kill-buffer llm-review-buffer-name))
  (dolist (buf (buffer-list))
    (when (string-prefix-p llm-review-test--test-dir (or (buffer-file-name buf) ""))
      (kill-buffer buf)))
  (when (file-directory-p llm-review-test--test-dir)
    (delete-directory llm-review-test--test-dir t)))

(ert-deftest llm-review-test-load-and-markers ()
  "Test loading findings JSON, marker creation, and insertion-type t."
  (llm-review-test--setup)
  (unwind-protect
      (let* ((json-path (expand-file-name "findings.json" llm-review-test--test-dir))
             (findings-json
              (concat "[{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 2,"
                      "\"end_line\": 4,"
                      "\"title\": \"Unused function one\","
                      "\"reason\": \"Function is never referenced.\","
                      "\"action\": \"delete\""
                      "},{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 9,"
                      "\"end_line\": 10,"
                      "\"title\": \"Unused function two\","
                      "\"reason\": \"Stub function.\","
                      "\"action\": \"delete\""
                      "}]")))
        (with-temp-file json-path
          (insert findings-json))

        (let ((buf (llm-review-load-file json-path llm-review-test--test-dir)))
          (should (buffer-live-p buf))
          (with-current-buffer buf
            (should (equal (length llm-review--findings) 2))
            (let* ((f1 (nth 0 llm-review--findings))
                   (f2 (nth 1 llm-review--findings))
                   (f1-s (alist-get 'start-marker f1))
                   (f1-e (alist-get 'end-marker f1))
                   (f2-s (alist-get 'start-marker f2))
                   (f2-e (alist-get 'end-marker f2)))
              ;; Verify markers are created
              (should (markerp f1-s))
              (should (markerp f1-e))
              (should (markerp f2-s))
              (should (markerp f2-e))

              ;; Verify insertion type is t
              (should (eq (marker-insertion-type f1-s) t))
              (should (eq (marker-insertion-type f1-e) t))
              (should (eq (marker-insertion-type f2-s) t))
              (should (eq (marker-insertion-type f2-e) t))

              ;; Verify initial line positions
              (should (equal (llm-review--finding-current-lines f1) '(2 . 4)))
              (should (equal (llm-review--finding-current-lines f2) '(9 . 10)))))))
    (llm-review-test--teardown)))

(ert-deftest llm-review-test-prevent-line-drift ()
  "Verify that live markers prevent line-number drift when edits occur."
  (llm-review-test--setup)
  (unwind-protect
      (let* ((json-path (expand-file-name "findings.json" llm-review-test--test-dir))
             (findings-json
              (concat "[{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 2,"
                      "\"end_line\": 4,"
                      "\"title\": \"Unused function one\","
                      "\"reason\": \"Function is never referenced.\","
                      "\"action\": \"delete\""
                      "},{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 9,"
                      "\"end_line\": 10,"
                      "\"title\": \"Unused function two\","
                      "\"reason\": \"Stub function.\","
                      "\"action\": \"delete\""
                      "}]")))
        (with-temp-file json-path (insert findings-json))
        (let ((buf (llm-review-load-file json-path llm-review-test--test-dir)))
          (with-current-buffer buf
            (let* ((f2 (nth 1 llm-review--findings))
                   (src-buf (alist-get 'buffer f2)))
              ;; Insert 5 new lines at the top of the source file
              (with-current-buffer src-buf
                (save-excursion
                  (goto-char (point-min))
                  (insert "# Injected line A\n# Injected line B\n# Injected line C\n")))

              ;; f2 markers should have dynamically shifted down by 3 lines!
              (should (equal (llm-review--finding-current-lines f2) '(12 . 13)))

              ;; Snippet still extracts the exact target text
              (let ((snippet (llm-review--format-snippet f2)))
                (should (string-match-p "unused_func_two" snippet)))))))
    (llm-review-test--teardown)))

(ert-deftest llm-review-test-delete-command ()
  "Test `d' command: deletes code block, cleans up markers, and refreshes UI."
  (llm-review-test--setup)
  (unwind-protect
      (let* ((json-path (expand-file-name "findings.json" llm-review-test--test-dir))
             (findings-json
              (concat "[{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 2,"
                      "\"end_line\": 4,"
                      "\"title\": \"Unused function one\","
                      "\"reason\": \"Delete me\","
                      "\"action\": \"delete\""
                      "},{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 9,"
                      "\"end_line\": 10,"
                      "\"title\": \"Unused function two\","
                      "\"reason\": \"Delete me too\","
                      "\"action\": \"delete\""
                      "}]")))
        (with-temp-file json-path (insert findings-json))
        (let ((buf (llm-review-load-file json-path llm-review-test--test-dir)))
          (with-current-buffer buf
            ;; Move point to finding 1
            (goto-char (point-min))
            (re-search-forward "Unused function one")
            (let* ((f1 (llm-review-current-finding))
                   (s-marker (alist-get 'start-marker f1))
                   (e-marker (alist-get 'end-marker f1))
                   (src-buf (alist-get 'buffer f1)))
              ;; Execute deletion
              (let ((llm-review-confirm-delete nil))
                (call-interactively #'llm-review-delete))

              ;; Markers for finding 1 must be cleaned up (nil position)
              (should (null (marker-position s-marker)))
              (should (null (marker-position e-marker)))

              ;; Finding 1 must be removed from the review list
              (should (equal (length llm-review--findings) 1))
              (should (equal (alist-get 'title (car llm-review--findings))
                             "Unused function two"))

              ;; Source buffer must no longer contain unused_func_one and must be saved
              (with-current-buffer src-buf
                (should-not (buffer-modified-p))
                (should-not (string-match-p "unused_func_one" (buffer-string)))
                (should (string-match-p "preserved_func" (buffer-string)))
                (should (string-match-p "unused_func_two" (buffer-string))))

              ;; File on disk must reflect deletion
              (with-temp-buffer
                (insert-file-contents (expand-file-name "sample.py" llm-review-test--test-dir))
                (should-not (string-match-p "unused_func_one" (buffer-string)))
                (should (string-match-p "preserved_func" (buffer-string))))

              ;; The remaining finding's line numbers must automatically adjust!
              (let ((f2 (car llm-review--findings)))
                ;; Initially lines 9-10; after 3-line deletion, now lines 6-7
                (should (equal (llm-review--finding-current-lines f2) '(6 . 7))))))))
    (llm-review-test--teardown)))

(ert-deftest llm-review-test-dismiss-command ()
  "Test `x' command: dismisses finding without modifying source file."
  (llm-review-test--setup)
  (unwind-protect
      (let* ((json-path (expand-file-name "findings.json" llm-review-test--test-dir))
             (findings-json
              (concat "[{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 2,"
                      "\"end_line\": 4,"
                      "\"title\": \"Unused function one\","
                      "\"reason\": \"Keep it anyway\","
                      "\"action\": \"delete\""
                      "}]")))
        (with-temp-file json-path (insert findings-json))
        (let ((buf (llm-review-load-file json-path llm-review-test--test-dir)))
          (with-current-buffer buf
            (goto-char (point-min))
            (re-search-forward "Unused function one")
            (let* ((f1 (llm-review-current-finding))
                   (s-marker (alist-get 'start-marker f1))
                   (src-buf (alist-get 'buffer f1)))
              (call-interactively #'llm-review-dismiss)

              ;; Marker freed
              (should (null (marker-position s-marker)))
              ;; 0 findings remaining
              (should (equal (length llm-review--findings) 0))

              ;; Source buffer unchanged!
              (with-current-buffer src-buf
                (should (string-match-p "unused_func_one" (buffer-string))))))))
    (llm-review-test--teardown)))

(ert-deftest llm-review-test-section-toggle ()
  "Test that magit-section-toggle collapses and expands preview sections."
  (llm-review-test--setup)
  (unwind-protect
      (let* ((json-path (expand-file-name "findings.json" llm-review-test--test-dir))
             (findings-json
              (concat "[{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 2,"
                      "\"end_line\": 4,"
                      "\"title\": \"Collapsible test\","
                      "\"reason\": \"Testing toggle\","
                      "\"action\": \"refactor\""
                      "}]")))
        (with-temp-file json-path (insert findings-json))
        (let ((buf (llm-review-load-file json-path llm-review-test--test-dir)))
          (with-current-buffer buf
            (goto-char (point-min))
            (re-search-forward "Collapsible test")
            (let ((sec (magit-current-section)))
              (should sec)
              ;; Initially expanded (hidden = nil)
              (should-not (oref sec hidden))
              ;; Press TAB to toggle
              (call-interactively #'magit-section-toggle)
              (should (oref sec hidden))
              ;; Press TAB again to re-expand
              (call-interactively #'magit-section-toggle)
              (should-not (oref sec hidden))))))
    (llm-review-test--teardown)))

(ert-deftest llm-review-test-action-filtering ()
  "Test filtering findings by action and clearing the filter."
  (llm-review-test--setup)
  (unwind-protect
      (let* ((json-path (expand-file-name "findings.json" llm-review-test--test-dir))
             (findings-json
              (concat "[{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 2,"
                      "\"end_line\": 4,"
                      "\"title\": \"Unused function one\","
                      "\"reason\": \"Delete me\","
                      "\"action\": \"delete\""
                      "},{"
                      "\"file\": \"sample.py\","
                      "\"start_line\": 6,"
                      "\"end_line\": 7,"
                      "\"title\": \"Simplify preserved function\","
                      "\"reason\": \"Refactor me\","
                      "\"action\": \"refactor\""
                      "}]")))
        (with-temp-file json-path (insert findings-json))
        (let ((buf (llm-review-load-file json-path llm-review-test--test-dir)))
          (with-current-buffer buf
            ;; Initially, all 2 findings are visible
            (should (equal (length (llm-review--visible-findings)) 2))
            (should (string-match-p "Unused function one" (buffer-string)))
            (should (string-match-p "Simplify preserved function" (buffer-string)))

            ;; Filter by "delete"
            (llm-review-filter-by-action "delete")
            (should (equal (length (llm-review--visible-findings)) 1))
            (should (string-equal llm-review--action-filter "delete"))
            (should (string-match-p "Unused function one" (buffer-string)))
            (should-not (string-match-p "Simplify preserved function" (buffer-string)))
            (should (string-match-p "FILTER: DELETE" (buffer-string)))

            ;; Clear filter with 'F' / llm-review-clear-filter
            (llm-review-clear-filter)
            (should (null llm-review--action-filter))
            (should (equal (length (llm-review--visible-findings)) 2))
            (should (string-match-p "Unused function one" (buffer-string)))
            (should (string-match-p "Simplify preserved function" (buffer-string)))

            ;; Filter by "refactor"
            (llm-review-filter-by-action "refactor")
            (should (equal (length (llm-review--visible-findings)) 1))
            (should-not (string-match-p "Unused function one" (buffer-string)))
            (should (string-match-p "Simplify preserved function" (buffer-string)))

            ;; Clear filter with "all"
            (llm-review-filter-by-action "all")
            (should (null llm-review--action-filter))
            (should (equal (length (llm-review--visible-findings)) 2)))))
    (llm-review-test--teardown)))

(ert-deftest llm-review-test-delete-crlf-line-endings ()
  "Test that deletion works cleanly on DOS/Windows CRLF line endings."
  (llm-review-test--setup)
  (unwind-protect
      (let* ((crlf-file (expand-file-name "crlf_sample.py" llm-review-test--test-dir))
             (json-path (expand-file-name "findings.json" llm-review-test--test-dir)))
        ;; Write file with explicit CRLF line endings
        (with-temp-file crlf-file
          (setq buffer-file-coding-system 'raw-text)
          (insert "line1\r\ndef to_delete():\r\n    pass\r\nline4\r\n"))
        (with-temp-file json-path
          (insert "[{\"file\": \"crlf_sample.py\", \"start_line\": 2, \"end_line\": 3, \"title\": \"Delete CRLF\", \"action\": \"delete\"}]"))
        (let ((buf (llm-review-load-file json-path llm-review-test--test-dir)))
          (with-current-buffer buf
            (goto-char (point-min))
            (re-search-forward "Delete CRLF")
            (let ((llm-review-confirm-delete nil))
              (call-interactively #'llm-review-delete)))
          ;; Verify source buffer has clean line boundaries with the block deleted
          (let ((src-buf (find-file-noselect crlf-file)))
            (with-current-buffer src-buf
              (should-not (string-match-p "to_delete" (buffer-string)))
              (should (string-match-p "line1" (buffer-string)))
              (should (string-match-p "line4" (buffer-string)))))))
    (llm-review-test--teardown)))

(ert-deftest llm-review-test-project-directory-reviews ()
  "Test automatic discovery and loading of reviews in `llm-review-directory'."
  (llm-review-test--setup)
  (unwind-protect
      (let* ((review-dir (expand-file-name llm-review-directory llm-review-test--test-dir))
             (rev1 (expand-file-name "review-20261026-100000.json" review-dir))
             (rev2 (expand-file-name "review-20261026-110000.json" review-dir)))
        (make-directory review-dir t)
        ;; Write first review
        (with-temp-file rev1
          (insert "[{\"file\": \"sample.py\", \"start_line\": 2, \"end_line\": 4, \"title\": \"Older Review Finding\", \"action\": \"delete\"}]"))
        ;; Ensure timestamp difference between files
        (sleep-for 0.05)
        ;; Write second review (newer)
        (with-temp-file rev2
          (insert "[{\"file\": \"sample.py\", \"start_line\": 6, \"end_line\": 7, \"title\": \"Newer Review Finding\", \"action\": \"refactor\"}]"))

        ;; Verify listing sorted newest first
        (let ((files (llm-review--list-review-files llm-review-test--test-dir)))
          (should (equal (length files) 2))
          (should (equal (car files) rev2)))

        ;; Verify `llm-review' automatically loads the latest review
        (let ((buf (llm-review llm-review-test--test-dir)))
          (with-current-buffer buf
            (should (string-match-p "Newer Review Finding" (buffer-string)))
            (should-not (string-match-p "Older Review Finding" (buffer-string))))))
    (llm-review-test--teardown)))

(ert-deftest llm-review-test-inhibit-formatters-on-save ()
  "Test that auto-formatters on `before-save-hook' are inhibited during delete."
  (llm-review-test--setup)
  (unwind-protect
      (let* ((json-path (expand-file-name "findings.json" llm-review-test--test-dir))
             (hook-called nil)
             (test-hook (lambda () (setq hook-called t))))
        (with-temp-file json-path
          (insert "[{\"file\": \"sample.py\", \"start_line\": 2, \"end_line\": 4, \"title\": \"Delete Hook Test\", \"action\": \"delete\"}]"))
        (let ((buf (llm-review-load-file json-path llm-review-test--test-dir)))
          (with-current-buffer buf
            (let* ((f1 (car llm-review--findings))
                   (src-buf (alist-get 'buffer f1)))
              (with-current-buffer src-buf
                (add-hook 'before-save-hook test-hook nil t))
              (goto-char (point-min))
              (re-search-forward "Delete Hook Test")
              (let ((llm-review-confirm-delete nil))
                (call-interactively #'llm-review-delete))
              ;; Verify hook was NOT called
              (should-not hook-called)
              ;; Verify buffer was nevertheless saved to disk
              (with-current-buffer src-buf
                (should-not (buffer-modified-p)))))))
    (llm-review-test--teardown)))

(provide 'llm-review-test)

;;; llm-review-test.el ends here
