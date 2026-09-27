# MR text — `kupfer/packages/pkgbuilds` (branch `dev`)

Ready to paste. Everything below was written before the first flash. "What works" is what
CI verifies by inspecting the packages and the generated boot image; the hardware status of
the MediaTek WiFi gets its own section further down, because "it builds" and "it works" are
different claims and it is worth not blurring them.

CI status: **green**. Run `36310845797` (commit `0497987`) of
`.github/workflows/build.yaml` in `criollojoel10/begonia-kupfer-linux`, flavour
`plasma-mobile`, from a clean runner with no cache, produces the image and passes
every check listed under "What works" below. Artifact:
`kupfer-begonia-plasma-mobile` (id 10929910559).

---

## Title

`mt6785: add Xiaomi Redmi Note 8 Pro (begonia) — first MediaTek device`

Open it as `Draft:` while the port has not booted on the phone, per the porting guidelines;
drop the prefix once it has been tested. The WiFi driver is not the reason for the prefix:
its author verified it on this phone, see the WiFi verification section below.

## Body

### Summary

Adds `mt6785-xiaomi-begonia`: the first MediaTek device in Kupfer. It is a port of the
postmarketOS port for the same phone, so the deviceinfo, the boot layout and the panel/touch
stack are the ones pmOS already uses, translated to the Arch packaging of this repo.

Nothing MediaTek-specific is touched outside the three new packages. The two changes to
existing packages are packaging-only and are called out separately below, because they are the
part worth reviewing first.

### Packages

| Package | What it is |
|---|---|
| `linux/mt6785` | `pkgbase=linux-mt6785`, kernel `6.16.4` from the author's fork (`minorum/linux`) of `mt6785-mainline/linux`, pinned to `3a1ea76942` — the head of `begonia-conn-wifi`, i.e. the tip of the forward-port described below. The fork's own `6.16` branch is still at `203a993f`, which is the pmaports base tag, and that base has no MediaTek connectivity stack; hence the pin. `Image.gz` + dtbs, `extra_config` on top of pmaports' config. |
| `firmware/mt6785-xiaomi-begonia` | MediaTek connectivity blobs, novatek panel/touch firmware, Realtek dongle firmware |
| `device/device-mt6785-xiaomi-begonia` | the `deviceinfo` (taken from pmaports at a fixed commit, plus the few attributes Kupfer needs), `/etc/machine-info`, the `mkinitcpio.conf.d` snippet, `empty.dtbo`, `mediatek-wifi.service`, and one libalpm hook that re-asserts Kupfer's `mkinitcpio.conf` |

### What works

- **Builds green**, Plasma Mobile flavour, from a clean runner, in GHA
  (run `36310845797`, ~50 min; the kernel is the slow part).
- **Boot image is correct for this bootloader**: `header_version=2` (DTB as a separate
  segment), `--recovery_dtbo` with a 136-byte `empty.dtbo`, the pmaports load addresses
  (base `0x40078000` + offsets), page size 2048. The aboot of begonia rejects a v0/v1
  header with a DTB, and without the recovery dtbo it never finds the panel override.
  CI parses the boot image header and asserts all of this.
- **Panel and touch load from the initramfs**: `lm36274_bl`, `lm363x-regulator`,
  `novatek-nvt-ts-spi`, `panel-novatek-nt36672a` and `ti-lmu` are in
  `deviceinfo_modules_initfs`, and the novatek firmware blob is in the initramfs `FILES`
  list (the panel is powered before the rootfs exists).
- **Tianma panel variant**: the 6.16 DTB only declares the CSOT panel, so the firmware
  package takes a `_panel=` switch and installs the Tianma binary under the CSOT name when
  asked. Verified on pmOS 6.16.4 that this is what makes the touch axes correct.
- **MediaTek internal WiFi stack compiles and is autostarted**: `mtk-vendor-btif`,
  `wmt_drv` and `wlan_gen4m` are built, the seven connectivity blobs are installed under
  `/usr/lib/firmware/mediatek/`, and `mediatek-wifi.service` loads them in the order the
  vendor driver requires (`btif` → `wmt_drv` → `wlan_gen4m` → the `1` write to
  `/dev/wmtWifi`). This needed `CONFIG_CFG80211_WEXT=y`: `wlan_gen4m.ko` calls
  `wireless_send_event()`, and without wireless extensions modpost fails the whole kernel
  with `"wireless_send_event" [...] undefined!`. The driver itself does work on begonia, but
  nobody has run it through this packaging; see the WiFi verification section below.
- **USB dongles** (ethernet, WiFi, BT, serial) are all in the image, so a hub is a working
  fallback for anything the SoC does not do.

### What does not work

- **Internal Bluetooth: everything except the driver is already there, and the driver does
  not exist.** This is not a packaging gap, so no firmware blob, service or `modprobe` fixes
  it. The interesting part is *why*, because it is not a missing-config kind of failure.
  - The phone carries the same BTIF block the working WiFi runs on. The connectivity MCU,
    the WMT control channel and the STP transport are one stack, and on begonia the live
    STP transport *is* BTIF (everything goes out through `mtk_wcn_btif_write`).
  - The device tree node exists in mainline and is enabled by default: `btif@1100c000`
    (`compatible = "mediatek,btif"`, three `reg` ranges, IRQs 138/155/154, clocks
    `btifc`/`apdmac`) in `arch/arm64/boot/dts/mediatek/mt6785.dtsi`. Our
    `mtk-vendor-btif.ko` binds it, the `bt` firmware blob the WiFi stack already loads
    (`soc1_0_ram_bt_2a_1_hdr.bin.zst`) is the one for it, and `BGF_EINT` (`GIC_SPI 321`) is
    wired in `mt6785-xiaomi-begonia.dts`.
  - What is missing is the HCI layer, the driver that would hand this transport to BlueZ.
    Nothing in `drivers/bluetooth/` consumes BTIF, and there is no `hci_register_dev()` call
    anywhere under `drivers/misc/mediatek/`. So there is no `hci0`, and BlueZ has nothing to
    bind to, no matter how the modules are ordered.
  - The two plausible shortcuts both fail. `btmtkuart.c` is the only MTK HCI driver in the
    tree and it drives a *separate* BT chip over a real UART (`mt7622`, `mt7663u`, `mt7668u`
    — router SoCs; the phone has none on-die), and the vendor userspace `mtk_bt_stack` is
    not redistributable. A vendor-style 8250-BTIF shim is not an option either: that
    approach (`8250_btif` plus `btmtkuart_hci`) was proposed in 2017 and never upstreamed.
  - A USB BT dongle works, `btusb` is in the image. The `bt` blob stays in the firmware
    package because it is part of the set the WiFi bring-up loads.

- **No modem**, same as pmOS mainline for this SoC.

### Verification status of the internal WiFi

Worth being precise here, because "it has never been run" and "nobody has run it" are very
different statements for this driver.

- **The driver works on this phone, verified by the person who wrote it.** The forward-port
  is `mt6785-mainline/linux` MR !2, *"Draft: begonia (MT6785): conn/WiFi vendor
  forward-port"*, which states that `wlan0` scans and associates on 2.4/5 GHz, with DHCP and
  ping verified on hardware. Its history is consistent with that: commit `b8c1b8b5` ("Verified
  on hardware: this clears the 'no hif info' gate; STP/BTIF now activates") and the live
  register dumps in `0468921f` are bring-up records, not speculation. This package builds the
  tip of that series (`3a1ea76942`).
- **Nobody has run this stack on begonia outside that bring-up.** MR !2 has zero comments and
  nobody has replied to it, so there is no second report to lean on. It is a cross-fork MR
  (author's fork `minorum/linux` → `mt6785-mainline/linux`) and it has sat there since June
  2026, which is a reasonable thing to expect for a ~545k-line vendor import labelled "not
  proposing merge yet". We are the first to take it through Kupfer, and the first to try it
  on pmOS with this packaging.
- The `RUNTIME-UNPROVEN` marker that *is* in the tree is narrower and older than that. It
  sits in the kernel file the port adds for the trigger,
  `drivers/misc/mediatek/connectivity/common/common_main/linux/wmt_wifi_trigger.c:16`, as a
  to-do for whoever is porting it: *"compile/link verified only ... the end-to-end bring-up has
  not been exercised on a device"*, and it only questions the `func_on` ordering. Its commit
  `ac488ea5` is 2026-06-18 02:27; the hardware-verified ones are 08:18 (`b8c1b8b5`) and 09:25
  (`0468921f`) the same day. The comment was simply never updated. It is not a verdict on the
  driver as a whole, and it is not in any file of this port.
- One worry I checked and set aside: `WIFI_EINT` and the `gpio_combo_*` pins are missing from
  the DTS. Those belong to the superseded reimplementation path (`MTK_CONNINFRA_MT6785`, which
  MR !2 turns *off* on purpose because it conflicts with the vendor consys code), not to the
  forward-port that actually runs. That reading is mine, not the author's.
- So the open question is packaging, not silicon: whether the modules load in the order the
  driver needs, whether the firmware lands where the driver looks for it, and whether the `1`
  write behaves as it did in the author's bring-up. `mtk-wifi-test.sh` in the port repository
  checks exactly those three things, and its step 8 dumps the driver's own WMT diagnostic
  proc files if `wlan0` does not appear.

### Not tested on hardware

The image has never been flashed yet: everything above is verified by inspecting the
packages and the generated boot image in CI, not on the phone. Specifically unverified:

- Whether the MediaTek internal WiFi comes up under Plasma Mobile, with the load order and
  trigger described above. The USB WiFi dongles are the fallback.
- Panel and touch on the device, and whether Plasma Mobile comes up.
- Battery, suspend, camera, sensors.

### The two changes to existing packages

These are the reason this is not just three new directories. Both are `pkgrel` bumps so the
local build wins over the prebuilt, and both are packaging-only.

1. **`boot/android-bootimg-updater` `0.5-1` → `0.5-2`**: `update-bootimg.sh` gains
   `--recovery_dtbo "$deviceinfo_recovery_dtbo"` when that attribute is set. The `dev`
   branch already branches on `header_version`, but it never mentions `dtbo` at all (zero
   matches in the whole repo), so a v2 device is built without the recovery dtbo it needs.
   Without this, begonia does not boot.
2. **`main/mkbootimg-git` `r254-2` → `r254-3`**: Python 2 integer division. This is the same
   fix that landed in pmOS' `mkbootimg`; without it `mkbootimg` truncates the load addresses
   and the resulting boot image has wrong segments.

If a maintainer prefers to take these two as separate MRs against the packages themselves,
this port still works as-is: it only needs the three new packages plus the same `pkgrel`
bumps, so the local build keeps winning over the prebuilts.

### How to test

This is the stock flow, nothing device-specific: fork this repo, then

```
kupferbootstrap config init                                              # ~/.config/kupfer/kupferbootstrap.toml
kupferbootstrap config profile init begonia                               # [profiles.begonia]
kupferbootstrap packages update                                           # refresh PKGBUILDs.git + SRCINFO, pulls this MR
kupferbootstrap image build                                               # -> mt6785-xiaomi-begonia-plasma-mobile-{full,boot,root}.img
kupferbootstrap image flash abootimg                                      # dumps aboot.img and flashes boot
kupferbootstrap image flash full userdata                                  # flashes the full image to userdata
```

with `device = "mt6785-xiaomi-begonia"` and `flavour = "plasma-mobile"` in the profile. Requires
an unlocked bootloader. `kupferbootstrap image flash` takes `--confirm` if you want it to ask
first.

Two things begonia needs that the stock flow does not do on its own:

- **`fastboot erase dtbo`.** The bootloader needs the `empty.dtbo` that is inside `aboot.img`;
  a leftover Android `dtbo` contradicts it and puts the phone in a boot loop.
  `kupferbootstrap image boot` already does this erase, so the `image boot` path is fine.
- **A vbmeta image flashed with `--flags 2`.** With flags 0 LK refuses the boot and drops back
  to fastboot. `avbtool make_vbmeta_image --flags 2 --padding_size 2048` is all it takes.

Flashing the raw image is also what can kill `fastboot` (`load_sparse_file()` allocates the
whole image in RAM, 4.7 GB peak on the 6.7 GiB rootfs (7.2 GB), and `systemd-oomd` kills it even with
swap), so convert with `img2simg` first and flash the `.simg` without `-S`. Kupfer's own
`--split-size` path does the same thing internally.

### Maintainer notes

- Happy to keep maintaining this. Everything MediaTek-specific is confined to the three new
  packages, so an upstream change to the shared boot tooling does not have to be merged here
  for this device to keep working.
- This port is not a fork of anything: the deviceinfo is imported from pmaports at a fixed
  commit (`6c223d3`), the same way `device-sdm845-xiaomi-beryllium` imports its own.
- `packages check --ci-mode` is clean on all five packages, and CI runs the equivalent. The
  layout follows the porting guidelines: `device/`, `linux/`, `firmware/`, and a `.gitignore`
  next to every `PKGBUILD` that downloads or generates files.
- One thing a maintainer may want to know because it is device-independent: if `mkinitcpio`
  is ever reinstalled in the same transaction that does not touch `/etc/kupfer/*`, the
  `50-mkinitcpio-overwrite` hook does not re-run and `/etc/mkinitcpio.conf` is left as
  Arch's stock one, which silently produces an initramfs without `rootfsdetect`,
  `rootfsresize` or `firmwaresearchpath`. The device package here ships
  `80-mkinitcpio-begonia.hook` so this device does not depend on that happening to go
  well. The number is not cosmetic: libalpm runs `PostTransaction` hooks in filename
  order, and the boot image *embeds* the initramfs, so the hook has to run before
  `91-android-bootimg-updater` rebuilds `aboot.img`; hence 80 and not 95. As a second
  line of defence the hook calls `update-bootimg` itself, so the result does not depend
  on the relative order at all. (The stock `systemd` hook also `add_module`s
  `crypto_lz4`, so without `CONFIG_CRYPTO_LZ4=m` in the kernel the build fails in the
  chroot with `module not found: 'crypto_lz4'`; the extra_config sets it.) If it is
  deemed general enough, it belongs in `boot/mkinitcpio-kupfer-hooks`.
- Ask me anything, Matrix `#kupfer-community`.

### Sources

Credit where it is due: none of the MediaTek work here is ours.

- **The connectivity stack** is `mt6785-mainline/linux` MR !2 and its companion firmware MR
  `mt6785-mainline/firmware` MR !1, both by minorum, who wrote the forward-port and tested
  it on his own begonia. We only package it.
- **Everything else** (deviceinfo, panel/touch, kernel config) comes from pmaports
  `device-xiaomi-begonia`, `firmware-xiaomi-begonia` and
  `linux-postmarketos-mediatek-mt6785` at a fixed commit.
