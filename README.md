# Background webmentions for Idno (Known)

Send webmentions in the background instead of while you wait for a post to save.

## The problem

When you publish a blog post (a `Text` entry), Idno sends webmentions for each link synchronously before the page 
responds. Each linked page has to be fetched and checked for a webmention endpoint, so a post with many links, or with a 
few slow or dead links, can take minutes to save.
On one blog the symptom was a `Maximum execution time of 30 seconds exceeded` fatal error on save.

## Why this is a small change

Idno already has a background queue for this. The `Status` post type uses it:

```php
\Idno\Core\Idno::site()->queue()->enqueue('default', 'webmention/sendall', [ ... ]);
```

and `docs/install/advanced.md` describes the asynchronous queue and its worker. The `Text` post type
(blog posts) never switched over: it still calls `\Idno\Core\Webmention::pingMentions(...)` directly.
This repo has the one-block change for `Text`, plus the pieces needed to run the worker from cron on
ordinary shared hosting, including for sites installed in a subdirectory like `https://example.com/blog/`.

With Idno's default queue (`SynchronousQueue`), `enqueue()` runs the event immediately, exactly as before.
So the code change does nothing until you turn on the asynchronous queue.

## What changes

| Piece | What it does |
|---|---|
| `patches/0001-text-entry-queue-webmentions.patch` | `IdnoPlugins/Text/Entry.php` queues the webmentions instead of sending them |
| `event_queue = 'AsynchronousQueue'` in `config.ini` | Turns on Idno's background queue (documented in `docs/install/advanced.md`) |
| `scripts/run-queue.sh` | Runs the queue worker once. Called from cron every minute, with a lock so runs never overlap |
| `scripts/subdir-prepend.php` | Only for sites in a subdirectory: tells the command-line worker where the site lives |

Webmentions then go out within about a minute of each save, from the cron job.

## Install

### 1. Change `IdnoPlugins/Text/Entry.php`

Apply the patch from your Idno folder (it was made against the `dev` branch at commit `31663ae`):

```
cd /path/to/idno
patch -p1 --dry-run < /path/to/0001-text-entry-queue-webmentions.patch   # check first
patch -p1 < /path/to/0001-text-entry-queue-webmentions.patch
php -l IdnoPlugins/Text/Entry.php
```

Older versions may not match the patch exactly. In that case make the change by hand. In the
`if ($this->getAccess() == 'PUBLIC') {` block that follows `$autosave->clearContext('entry');`,
replace the `pingMentions(...)` call with:

```php
\Idno\Core\Idno::site()->queue()->enqueue('default', 'webmention/sendall', [
    'source' => $this->getURL(),
    'text' => \Idno\Core\Idno::site()->template()->parseURLs($this->getTitle() . ' ' . $this->getDescription()),
]);
```

Leave the `pingMentions` call in `deleteData()` alone. Back up the file first, because updating Idno
overwrites this change.

### 2. Turn on the asynchronous queue

Add this line to `configuration/config.ini`:

```
event_queue = 'AsynchronousQueue'
```

### 3. If you had switched webmentions off, switch them back on

Idno skips sending when the constant `IDNO_NOMENTION` is defined. If you defined it somewhere (a plugin,
for example), remove that line. Otherwise the worker sends nothing.

### 4. Subdirectory installs only: copy the helper

Idno works out its subdirectory in `Idno/start.php`, which only the web entry point (`index.php`) loads.
The command-line entry point (`idno.php`) never loads it. From the command line, a site at
`https://example.com/blog/` is therefore treated as `https://example.com/`, and the worker's call back to
your site goes to the wrong address.

Copy `scripts/subdir-prepend.php` to your home folder, outside the web root. `run-queue.sh` loads it for you.
Skip this step if Idno is at the root of your domain.

### 5. Set up the worker script

Copy `scripts/run-queue.sh` to your home folder, open it, and edit the five settings at the top
(`WEB_ROOT`, `SUBDIR`, `DOMAIN`, `PHP_BIN`, `HELPER`). Then:

```
chmod 700 ~/run-queue.sh
```

Requires `flock` (part of util-linux; present on most Linux hosts).

### 6. Test it by hand before adding cron

1. Save a post that has a few links. The save should return in a second or two.
2. Run the script's command with its output visible, to see what the worker does. Use the same
   values you put in `run-queue.sh`:

```
cd /path/to/webroot && HTTPS=on IDNO_DOMAIN=example.com IDNO_PORT=443 \
  ASYNC_WM_SUBDIR=blog php -d auto_prepend_file=$HOME/subdir-prepend.php \
  blog/idno.php service-event-queue --once
```

(For a root install, drop `ASYNC_WM_SUBDIR` and `-d auto_prepend_file=...`, and run `php idno.php ...`.)

A working run prints `Dispatching event ...: webmention/sendall` and then `Event ... completed.`

### 7. Add the cron job

Run the script every minute:

```
* * * * * /bin/bash /home/youraccount/run-queue.sh
```

## Troubleshooting

**`Event ... dispatched but may not have completed.`** The worker calls your site at
`/service/queue/dispatch/<id>` and expects JSON back. This message means it got something else.
Idno logs the address it calls. Look in the PHP error log for lines like
`Calling https://example.com/service/queue/dispatch/...`. If the address is missing your subdirectory,
the worker is calling the wrong place (see step 4). If it says `http://` and your site redirects to https,
check the `HTTPS=on` and `IDNO_PORT=443` values.

**`Error dispatching event ...: Response from service endpoint was not json`.** Same cause, with the address
wrong enough that the call failed or got an error page. Check the address as above.

**The same event dispatches every minute.** It isn't completing. The dispatch runs as a web request to
your own site, so PHP's `max_execution_time` applies. A post with many slow links can need more than the
default 30 seconds. Raise it for the site (for example in `.user.ini`), then watch the next run.

**Nothing is sent after a save.** The cron job may not be running, or `IDNO_NOMENTION` is still defined.

The PHP error log is the quickest place to see what the worker is doing. Where it is depends on your host.
On cPanel hosts it is often a file called `error_log`, written in the folder the command ran from.

## Trade-offs

- Webmentions go out up to about a minute after the save, not immediately.
- If the cron job stops, nothing is sent, and events wait in the queue until it runs again.
- Other background work moves to the same schedule: syndication, PubSubHubbub pings, and anything else
  that uses Idno's queue now runs on the cron job too.
- Updating Idno overwrites the `Entry.php` change, so keep the patch and reapply it.

## What was tested

On a shared cPanel host running Known 1.6.x, with the site in a `/blog` subdirectory: saving a blog post
with several links returned immediately. Running the worker by hand with the command in step 6 completed
the `webmention/sendall` events, and a webmention arrived at a receiving site (webmention.rocks). The cron job
was also seen dispatching events every minute; I did not separately confirm that each cron-run event completed.

The wrapper script's locking and command assembly were checked locally with a stand-in for PHP, not with a real Idno.
The patch is for `IdnoPlugins/Text/Entry.php` only. It applies cleanly to the `dev` branch at `31663ae` and
passes `php -l`, but I haven't run Idno's test suite against it.

## Other post types

Only `Status` and, with this patch, `Text` use the queue. The other types still send webmentions directly:
`Photo`, `Like`, `Checkin`, `Event`, `RSVP` and `Media`. See [CORE-PROPOSALS.md](CORE-PROPOSALS.md).

## License

Apache License 2.0, the same license as Idno. See [LICENSE](LICENSE).
