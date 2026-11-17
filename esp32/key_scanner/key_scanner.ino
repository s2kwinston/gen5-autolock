// key_scanner — BLE key-tag sensor for gen5-autolock (ESP32-S3, Arduino + NimBLE)
//
// The "dumb sensor" for the optional key-inside protection: scans for YOUR BLE key
// tag and streams presence over USB-CDC serial. ALL policy (debounce, the lock /
// hold decision) lives on the head unit in walkaway.sh — this only reports "heard
// it / didn't" each window. Setup and flashing: docs/key-sensor.md.
//
// >>> Before you flash: set TAG_ADDRESS below to your tag's Bluetooth address. <<<
//
// Wire protocol (LF-terminated), one line per scan window:
//     KEY 1 <rssi> <seq> <n>     tag heard this window (rssi = best dBm, n = devices heard)
//     KEY 0 0 <seq> <n>          the scan RAN for the full window and did not hear the tag
//     ERR <reason> <ms> <seq>    the scan did NOT run properly (start failed, ended early
//                                or with an error) — NOT evidence of absence
//     # <text>                   comments (startup, "TAG_ADDRESS not set", reboot notice)
// KEY 0 is a claim "I listened and it isn't here", so it is printed ONLY when the scan
// provably ran: onScanEnd fired with reason 0 AND the blocking scan lasted >= 80% of
// SCAN_MS. Otherwise ERR, which the head unit ignores: a deaf radio makes its feed go
// stale -> OFFLINE -> no lock. Three ERRs in a row reboot the board.
// n (distinct devices heard) is diagnostic only: a busy lot shows dozens, a deaf radio 0.
//
// Design notes:
//   - Arduino + NimBLE, NOT CircuitPython: presents a clean CDC serial device only,
//     no USB mass-storage drive (which would collide with the head unit's media stack
//     and NEMESIS's USB autorun on its one port), no REPL.
//   - Match by address only. A name match could pick up someone else's tag and hold
//     the lock off for no reason. The tag must use a fixed (static) address.
//   - Scan via callbacks with result storage OFF (setMaxResults(0) = "callbacks
//     only" in NimBLE 2.x): bounded memory in a crowded parking lot. NOTE: with
//     storage off, getResults() returns an EMPTY list — never read the key from it.
//   - Duty-cycled scan (SCAN_MS of each WINDOW_MS) to run cooler than a nonstop scan.
//     Keep SCAN_MS comfortably above the tag's advertising interval (~1 s).
//   - Loop watchdog: if the BLE stack ever wedges, the board reboots instead of going
//     silent (silence is already fail-safe on the head unit; this makes it recover).
//   - Build: see esp32/README.md (board settings: USB Mode = USB-OTG (TinyUSB),
//     USB CDC On Boot = Enabled; library "NimBLE-Arduino" by h2zero, 2.x).

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <ctype.h>
#include <string.h>

// ---- SET THIS: your key tag's Bluetooth address, as shown by nRF Connect ----------
// Upper or lower case both work, e.g. "AA:BB:CC:DD:EE:FF".
static const char*    TAG_ADDRESS = "00:00:00:00:00:00";
// -----------------------------------------------------------------------------------

static const uint32_t SCAN_MS    = 1200;                 // scan duration per window
static const uint32_t WINDOW_MS  = 2500;                 // total window (scan + idle) -> duty cycle
static const int      MIN_RSSI   = -100;                 // ignore adverts weaker than this

static char targetMac[18];      // TAG_ADDRESS, lower-cased (NimBLE prints addresses lower-case)
static bool tagConfigured = false;

static NimBLEScan* pScan = nullptr;
static uint32_t seq = 0;

// Written from the NimBLE host task during a scan, read by loop() after the scan ends.
// (onScanEnd runs BEFORE getResults() returns — NimBLEScan.cpp DISC_COMPLETE handler.)
static volatile bool tagSeen   = false;
static volatile int  tagRssi   = -127;
static volatile int  devCount  = 0;
static volatile bool scanEnded = false;
static volatile int  scanReason = -1;
static uint8_t failStreak = 0;
static const uint8_t MAX_FAILS = 3;          // consecutive ERR windows before a reboot

static void consider(const NimBLEAdvertisedDevice* dev) {
  if (dev == nullptr) return;
  int rssi = dev->getRSSI();
  if (rssi < MIN_RSSI) return;
  if (dev->getAddress().toString() != targetMac) return;
  tagSeen = true;
  if (rssi > tagRssi) tagRssi = rssi;
}

class TagCallbacks : public NimBLEScanCallbacks {
  // onDiscovered fires on a device's first advert in the scan (duplicates filtered);
  // onResult once its result is complete. Check both so nothing hides the tag.
  void onDiscovered(const NimBLEAdvertisedDevice* dev) override { devCount = devCount + 1; consider(dev); }
  void onResult(const NimBLEAdvertisedDevice* dev) override { consider(dev); }
  void onScanEnd(const NimBLEScanResults& results, int reason) override {
    (void)results;
    scanReason = reason;                      // 0 = the scan ran its full duration
    scanEnded = true;
  }
};
static TagCallbacks tagCallbacks;

static void drainInput() {
  // The head unit never sends anything meaningful; if its tty echoes our lines back,
  // drop them so the USB RX buffer can't fill and stall the host side.
  while (Serial.available() > 0) Serial.read();
}

void setup() {
  Serial.begin(115200);
  delay(300);                                 // let CDC enumerate so the first lines aren't lost

  // Lower-case the configured address; accept it only if it looks like one and isn't
  // the placeholder. Unset -> the board reports nothing -> the head unit fails safe.
  size_t n = strlen(TAG_ADDRESS);
  if (n > 17) n = 17;
  for (size_t i = 0; i < n; i++) targetMac[i] = (char)tolower((unsigned char)TAG_ADDRESS[i]);
  targetMac[n] = '\0';
  tagConfigured = (strlen(TAG_ADDRESS) == 17) && strcmp(targetMac, "00:00:00:00:00:00") != 0;

  NimBLEDevice::init("");
  pScan = NimBLEDevice::getScan();
  pScan->setScanCallbacks(&tagCallbacks, false);
  pScan->setActiveScan(false);                // passive: the address is in every advert; no TX
  pScan->setInterval(45);
  pScan->setWindow(45);                       // window == interval: listen continuously while scanning
  pScan->setMaxResults(0);                    // callbacks only, store nothing (see header)
  enableLoopWDT();                            // reboot if loop() ever stops coming back (~5 s)
  Serial.print("# key_scanner up\n");
}

void loop() {
  if (!tagConfigured) {
    drainInput();
    Serial.print("# TAG_ADDRESS is not set - edit key_scanner.ino and flash again (docs/key-sensor.md)\n");
    delay(WINDOW_MS);
    return;
  }

  seq++;
  tagSeen = false;
  tagRssi = -127;
  devCount = 0;
  scanEnded = false;
  scanReason = -1;

  // Blocking scan for SCAN_MS; the callbacks above record the tag. The returned
  // results list is empty by design (setMaxResults(0)) and is ignored. If start()
  // fails, or a scan is already running, getResults() returns at once — caught below.
  uint32_t t0 = millis();
  pScan->getResults(SCAN_MS, false);
  uint32_t took = millis() - t0;
  pScan->clearResults();

  bool listened = scanEnded && scanReason == 0 && took >= (SCAN_MS * 8) / 10;

  drainInput();
  if (tagSeen) {
    // positive evidence stands on its own, even from a scan that then ended badly
    Serial.print("KEY 1 ");
    Serial.print((int)tagRssi);
    Serial.print(' ');
    Serial.print(seq);
    Serial.print(' ');
    Serial.print((int)devCount);
    Serial.print('\n');
  } else if (listened) {
    Serial.print("KEY 0 0 ");
    Serial.print(seq);
    Serial.print(' ');
    Serial.print((int)devCount);
    Serial.print('\n');
  } else {
    // NOT "absent": the radio didn't provably listen. The head unit ignores ERR lines.
    Serial.print("ERR ");
    Serial.print(scanEnded ? (int)scanReason : -1);
    Serial.print(' ');
    Serial.print(took);
    Serial.print(' ');
    Serial.print(seq);
    Serial.print('\n');
  }

  if (listened || tagSeen) {
    failStreak = 0;
  } else if (++failStreak >= MAX_FAILS) {
    Serial.print("# radio not listening, rebooting\n");
    Serial.flush();
    ESP.restart();
  }

  // Idle the remainder of the window (duty-cycle for heat). getResults() already
  // blocked for SCAN_MS, so sleep only the leftover.
  if (WINDOW_MS > SCAN_MS) delay(WINDOW_MS - SCAN_MS);
}
