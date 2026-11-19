# Is the song-playing architecture solid? A checklist you can run

Nothing that depends on YouTube can be guaranteed forever. This list turns
"I hope it works" into things you can see on your own phone in about ten
minutes. Re-run it after every update and whenever playback misbehaves.

## 1. One-tap self-test (30 seconds)
Settings → Playback Log → the **✔ (verified)** icon in the top bar.

It finds, downloads and saves a real, very stable video (the first YouTube
video ever, 19 s), checks the file is genuine audio, then removes it. Expect:

```
✓ Disk cache
✓ Find and download   …  <bytes>
✓ File is real audio  …  mp4/m4a  (or webm/opus)
✓ Saved for offline
✓ Total
PASS: the song pipeline works end to end on this device and network.
```
A FAIL names the stage and what to do (Network check, wait for a rate limit,
update the client definitions, …). It does **not** test sound: use section 2.

## 2. Things only a human can confirm
| Check | How | Pass |
|---|---|---|
| Sound | Search any song, tap it | Audible within ~5 s, plays to the end, next song starts |
| Instant skip | Tap next after the first song has played ~10 s | Next song starts at once (it was prefetched) |
| Offline replay | Airplane mode, replay a song you already played | Plays |
| Screen off | Lock the phone for 3+ minutes | Keeps playing |
| Lock-screen / notification | Pull down the shade | Play, pause, next work (needs notification permission) |
| Headphones | Unplug while playing | Pauses |
| Rapid skipping | Tap next 15 times quickly | Settles on one song, no error |
| Swipe away | Swipe the app from recents, reopen | Opens and plays normally |
| Queue edits | Reorder / remove in Up Next | Plays in the order shown |

If "Screen off" fails: Settings → Apps → Nebula → Battery → **Unrestricted**.

## 3. What is covered automatically
`flutter test` (347 tests, no phone needed): corrupt data, hostile servers,
rapid input, 150 random failure combinations of the download pipeline, and every
failure kind. It cannot reach YouTube, so it cannot catch YouTube changing.

## 4. How you find out it broke
- The self-test fails with a specific reason, or
- a song shows "YouTube refused the audio download (HTTP 403)", or
- Playback Log shows `resolver: client N failed` for every client.

Then: copy the log and send it. The fix is usually refreshing the client
definitions in `lib/services/youtube_clients.dart` from yt-dlp's
`yt_dlp/extractor/youtube/_base.py` (`INNERTUBE_CLIENTS`).
