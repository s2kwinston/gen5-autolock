# `ref/` — framework hash reference

The daemon can refuse to run if the vehicle framework on your head unit no longer
matches the build the lock transaction was verified against. This matters because an
OTA update can renumber service transaction codes — and a stale code could turn
"lock the doors" into something else entirely.

To use the gate (recommended), copy your **own** head unit's framework files here:

```sh
cp /system/framework/automotive.odex          ref/
cp /system/framework/automotive-service.odex   ref/
```

These are proprietary Hyundai/Kia binaries. They are specific to your firmware, they
are **not** redistributed with this project, and `.gitignore` keeps them out of the
repo (`ref/*.odex`). Keep them local.

If `ref/automotive.odex` / `ref/automotive-service.odex` are present, the daemon
compares the live `/system/framework` copies against them at startup and exits if they
differ. To skip the check entirely, set `CHECK_ODEX=0` at the top of `walkaway.sh`
(not recommended — you lose the protection against an OTA moving the lock code).
