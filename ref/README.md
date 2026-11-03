# Framework hash gate (`ref/`)

The daemon refuses to run unless the vehicle framework on your head unit is one the lock
transaction was verified against. This matters because an OTA update can renumber service
transaction codes — and a stale code could turn "lock the doors" into something else.

**How it decides** (gate on by default, `CHECK_ODEX=1`):

1. The md5 of the live `/system/framework/automotive.odex` and `automotive-service.odex`
   (toolbox `md5`) is compared with the verified builds listed in `walkaway.sh`
   (`KNOWN_MD5_*`). Currently: `CVEV.USA.0000.V015.012.260507` — the 2022 US Kia EV6.
   Match → it runs, nothing to set up.
2. Otherwise, if you have **pinned** your own head unit's copies into the reference
   directory, the live files must be byte-identical to them. Match → it runs.
3. Otherwise it logs `FATAL: framework is not a verified build and no pinned reference …`
   and exits. Deliberate: fail safe, never fire against an unverified framework.

## Accepting another firmware (pinning)

Pinning means "I accept this firmware as-is" — it does **not** verify the lock command on
it. Do it once you've checked that `IBCMService` transaction 5 is still `lockDoor` on your
build (see `docs/design.md` §6), or knowingly accept that risk.

**No shell needed:** insert the **ref-odex** USB stick
([`usb-sticks/ref-odex/`](../usb-sticks/ref-odex/)) with the car on and tap Yes. It copies
the two files below from your head unit into `/data/nemesis/gen5-autolock-ref/`, verifies
them byte-for-byte, and restarts the service. Run it again after a Kia software update to
re-pin (it says `REPLACED`) — only once you're sure the lock command is unchanged.

Or copy your **own** head unit's framework files into the reference directory by hand:

- **Installed as a NEMESIS package (recommended):** put them in
  `/data/nemesis/gen5-autolock-ref/`. This lives *outside* the package tree, so a package
  update won't wipe them (postinstall creates the directory for you):
  ```sh
  cp /system/framework/automotive.odex         /data/nemesis/gen5-autolock-ref/
  cp /system/framework/automotive-service.odex /data/nemesis/gen5-autolock-ref/
  ```
- **Running standalone:** put them in `ref/` next to `walkaway.sh`:
  ```sh
  cp /system/framework/automotive.odex         ref/
  cp /system/framework/automotive-service.odex ref/
  ```

Resolution order: `$GEN5_REF` → `$WALKAWAY_REF` → `/data/nemesis/gen5-autolock-ref/`
(if it exists) → `./ref` beside the script.

These are proprietary Hyundai/Kia binaries, specific to your firmware. They are **not**
redistributed with this project, and `.gitignore` keeps them out of the repo
(`ref/*.odex`). Keep them local. At startup the daemon compares the live
`/system/framework` copies against your references and exits if they differ.

## Turning the gate off

Set `CHECK_ODEX=0` **in the config file** (`/data/nemesis/gen5-autolock.conf`, or via the
custom-settings USB stick) — not by editing the script. Not recommended: you lose the
protection against an OTA moving the lock code.
