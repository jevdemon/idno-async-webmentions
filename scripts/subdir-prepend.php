<?php
// Tells the Idno command-line tools which subdirectory the site lives in.
//
// Idno works this out for web requests (Idno/start.php), but idno.php never loads that file,
// so from the command line a site at https://example.com/blog/ is treated as if it were at
// https://example.com/. The queue worker then calls the wrong address for every event.
//
// Used with:  php -d auto_prepend_file=/path/to/subdir-prepend.php idno.php ...
// The subdirectory comes from the ASYNC_WM_SUBDIR environment variable (no slashes), which
// run-queue.sh sets. If it is empty or unset, this file does nothing.

$asyncWmSubdir = trim((string) getenv('ASYNC_WM_SUBDIR'), '/');
if ($asyncWmSubdir !== '' && !defined('IDNO_SUBDIRECTORY')) {
    define('IDNO_SUBDIRECTORY', $asyncWmSubdir);
    if (!defined('KNOWN_SUBDIRECTORY')) {
        define('KNOWN_SUBDIRECTORY', IDNO_SUBDIRECTORY);
    }
}
unset($asyncWmSubdir);
