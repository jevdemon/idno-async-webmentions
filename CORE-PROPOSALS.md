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

