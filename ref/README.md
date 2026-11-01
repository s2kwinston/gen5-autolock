# Framework hash reference (`ref/`)

The daemon can refuse to run if the vehicle framework on your head unit no longer matches
the build the lock transaction was verified against. This matters because an OTA update
can renumber service transaction codes — and a stale code could turn "lock the doors" into
something else entirely.

**The gate is on by default (`CHECK_ODEX=1`), and with no reference files present the
daemon refuses to run** — it logs `FATAL: reference odex missing … — refusing to run` and
exits. That is deliberate: fail safe, never fire against an unverified framework. So you
must either supply the reference files or turn the gate off.

## Supply your own reference files

Copy your **own** head unit's framework files into the reference directory:

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
