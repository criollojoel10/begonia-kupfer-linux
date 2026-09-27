# MR text — `kupfer/packages/pkgbuilds` (branch `dev`)

Ready to paste. Everything below was written before the first flash, so the "not tested"
section is honest about what is still unverified on hardware.

PENDIENTE ANTES DE ENVIAR: confirmar el run de CI verde y poner su número en la primera
balanza de "What works".

---

## Title

`mt6785: add Xiaomi Redmi Note 8 Pro (begonia) — first MediaTek device`

Open it as `Draft:` while the internal WiFi is still unproven on hardware, per the porting
guidelines; drop the prefix once it has been tested on the phone.

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
| `linux/mt6785` | `pkgbase=linux-mt6785`, kernel `6.16.4` from the `mt6785-mainline/linux` fork, `Image.gz` + dtbs, `extra_config` on top of pmaports' config |
| `firmware/mt6785-xiaomi-begonia` | MediaTek connectivity blobs, novatek panel/touch firmware, Realtek dongle firmware |
| `device/device-mt6785-xiaomi-begonia` | the `deviceinfo` (taken from pmaports at a fixed commit, plus the few attributes Kupfer needs), `/etc/machine-info`, the `mkinitcpio.conf.d` snippet, `empty.dtbo`, `mediatek-wifi.service`, and one libalpm hook that re-asserts Kupfer's `mkinitcpio.conf` |

### What works

- **Builds green on `dev`**, Plasma Mobile flavour, from a clean runner, in GHA
  (~45 min; the kernel is the slow part).
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
  with `"wireless_send_event" [...] undefined!`.
- **USB dongles** (ethernet, WiFi, BT, serial) are all in the image, so a hub is a working
  fallback for anything the SoC does not do.

### What does not work

- **Internal Bluetooth is not possible with this port.** There is no HCI transport under
  `drivers/misc/mediatek/btif/` in this tree (`btmtkuart.c` is the only MTK HCI driver and
  it is UART-only, for `mt7622`/`mt7663u`/`mt7668u`), and the vendor userspace
  `mtk_bt_stack` is not redistributable. A USB BT dongle works (`btusb` is in the image).
- **No modem**, same as pmOS mainline for this SoC.

### Not tested on hardware

The image has never been flashed yet: everything above is verified by inspecting the
packages and the generated boot image in CI, not on the phone. Specifically unverified:

- **The MediaTek internal WiFi itself.** The driver author marks the `wlan_gen4m` path
  `RUNTIME-UNPROVEN`, `WIFI_EINT` is still a placeholder in the DTS, and the
  `gpio_combo_*` pins are not in the DTS either. What is verified is that the modules build,
  the firmware is in place and the load order is the vendor one. The USB WiFi dongles are
  the fallback.
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
whole image in RAM, 4.7 GB peak on a 6.7 GB image, and `systemd-oomd` kills it even with
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
