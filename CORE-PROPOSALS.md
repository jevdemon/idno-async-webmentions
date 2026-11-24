# Proposed changes to Idno core

Three small changes that would make background webmentions work without anything in this repo.
Everything below was read from the `dev` branch at commit `31663ae` (2026-11-23).

## 1. Queue webmentions for every post type

Only `IdnoPlugins/Status` sends webmentions through the queue. The others call
`\Idno\Core\Webmention::pingMentions(...)` directly while the author waits.

| File | Where |
|---|---|
| `IdnoPlugins/Status/Status.php` | **queued** (publish), direct in `deleteData()` |
| `IdnoPlugins/Text/Entry.php` | direct on publish and in `deleteData()` (see `patches/0001-text-entry-queue-webmentions.patch`) |
| `IdnoPlugins/Photo/Photo.php` | direct on publish |
| `IdnoPlugins/Media/Media.php` | direct on publish |
| `IdnoPlugins/Like/Like.php` | direct on publish and in `deleteData()` |
| `IdnoPlugins/Checkin/Checkin.php` | direct on publish and in `deleteData()` |
| `IdnoPlugins/Event/Event.php` | direct on publish and in `deleteData()` |
| `IdnoPlugins/Event/RSVP.php` | direct on publish and in `deleteData()` |

The change for each is the same one `Status` already has: pass the same two values (`source` and `text`) to
`queue()->enqueue('default', 'webmention/sendall', [...])`. The `webmention/sendall` listener in
`Idno/Core/Webmention.php` calls `pingMentions($data['source'], $data['text'])`, which is the same function,
so what gets sent is unchanged. With the default `SynchronousQueue`, `enqueue()` runs the event immediately,
so sites that haven't turned on the asynchronous queue see no difference.

The calls in `deleteData()` could be left as they are, since deleting a post is rare.

Only the `Text` change has been used on a live site. The other call sites are the same pattern but untested.

## 2. Tell the command-line tools about the subdirectory

`Idno/start.php` defines `IDNO_SUBDIRECTORY` for web requests, working it out from `PHP_SELF`. Only `index.php`
loads `start.php`. `idno.php` doesn't, so from the command line the constant is never defined, and
`Config::detectBaseURL()` (which does use it if present) builds `https://example.com/` for a site that really
lives at `https://example.com/blog/`.

The effect on my site: `service-event-queue` called `https://example.com/service/queue/dispatch/<id>`, which
returned a page that wasn't Idno's reply, and every event reported `dispatched but may not have completed`. This affects any site installed in a
subdirectory that uses the asynchronous queue.

A possible fix is to accept the subdirectory from the environment, next to `IDNO_DOMAIN` and `IDNO_PORT`, which
`detectBaseURL()` already reads:

```php
// in the console branch of Config::detectBaseURL(), where IDNO_DOMAIN is used
$subdir = defined('IDNO_SUBDIRECTORY') ? IDNO_SUBDIRECTORY : (getenv('IDNO_SUBDIRECTORY') ?: '');
if ($subdir !== '') {
    $url .= '/' . trim($subdir, '/');
}
```

This is a sketch, not a tested patch. `scripts/subdir-prepend.php` in this repo is the workaround I'm using in
the meantime.

## 3. A clearer message when the dispatch call returns the wrong thing

When the worker's call to `/service/queue/dispatch/<id>` doesn't return Idno's expected reply,
`service-event-queue` prints `dispatched but may not have completed`, with no hint about which address it
called. The address only appears in the debug log. Printing it in that message would have saved a lot of time.

## Draft issue for idno/idno

**Title:** Send webmentions in the background for blog posts (Text), like Status already does

**Body:**

> When I publish a blog post, Idno sends webmentions to every link in it before the page responds, one after
> another. On posts with many links, or a few slow or dead ones, saving takes minutes, and I've hit
> `Maximum execution time of 30 seconds exceeded` (the stack trace ends in `Scanner.php`).
>
> `IdnoPlugins/Status` already avoids this by calling
> `queue()->enqueue('default', 'webmention/sendall', [...])`, and the docs describe the asynchronous queue
> (`docs/install/advanced.md`). `IdnoPlugins/Text/Entry.php` still calls `Webmention::pingMentions()` directly.
> With the default `SynchronousQueue`, `enqueue()` runs the event immediately, so the change doesn't alter
> behavior for sites that haven't turned on the asynchronous queue.
>
> I've put a patch for `Text/Entry.php`, a cron wrapper for shared hosting, and notes on the other post types
> here: <link to your repo>. I've run it on my own site with the asynchronous queue and a cron job running
> `service-event-queue --once`.
>
> I also found that the worker can't reach a site installed in a subdirectory (`https://example.com/blog/`),
> because `idno.php` never loads `start.php`, so `IDNO_SUBDIRECTORY` isn't defined. The worker then calls
> `https://example.com/service/queue/dispatch/...`. The repo has a workaround, and I can open a separate
> issue for it if you'd prefer.
>
> Happy to turn any of this into pull requests.
