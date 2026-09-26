# Kupfer Linux for Xiaomi Redmi Note 8 Pro (begonia)

Port: **pmOS (Alpine) → Kupfer Linux (Arch)** para Xiaomi Redmi Note 8 Pro (`xiaomi-begonia`,
SoC MediaTek **MT6785**). **Primer dispositivo MediaTek soportado por Kupfer** (hasta ahora los 24
dispositivos son Qualcomm: msm8916/8953/sdm670/sdm845).

Kupfer: *"to Arch what postmarketOS is to Alpine"* — derivada de Arch Linux ARM, infraestructura
heredada de pmOS (`deviceinfo`, `kupferbootstrap`), boot vía Android boot.img (`aboot`).

Base elegida: rama **`dev`** de `gitlab.com/kupfer/packages/pkgbuilds`, no `main`. Motivo: `main` no
tiene el flavour `flavour-plasma-mobile` ni el split de paneles, que es justamente lo que se quiere
flashar. `dev` es la rama donde upstream desarrolla, así que este port va a corde con lo que la
comunidad.mergea primero.

---

## Estado

| Etapa | Estado |
|---|---|
| Investigación (arquitectura Kupfer + datos del device) | ✅ |
| Investigación de precedentes MTK / no-Qualcomm en Kupfer | ✅ |
| PKGBUILDs de device / kernel / firmware | ✅ |
| Parche `update-bootimg.sh` (header v2 + recovery_dtbo) | ✅ |
| Build imagen Plasma Mobile (GHA, base `dev`) | ⏳ en curso |
| Flasheo y verificación en device | ⏳ pendiente |

## Investigación: no hay ningún port MediaTek que nos preceda

Se revisó el estado real del proyecto antes de escribir nada, para saber si existía una guía:

- **24 dispositivos** en `dev`, **todos Qualcomm** (msm8916, msm8953, sdm670, sdm845).
- De ~100 merge requests, **cero de MediaTek**.
- De ~61 branches del repo de pkgbuilds, **ninguna de MediaTek**.
- Lo único no-Qualcomm son 2 drafts de **Exynos** (MR 159 / 162, Nexus 10), **cerrados sin
  mergear**. El motivo declarado en el hilo son problemas de **armv7h**, no el SoC: begonia es
  `aarch64`, así que esa razón no aplica.

Conclusión: **no hay guía previa, somos de verdad el primer port MTK de Kupfer.** El build con más
probabilidad de fallar es este, no por culpa del MediaTek en sí sino porque nadie recorrió antes
los mismos pasos. Contacto para dudas: Matrix, espacio `#kupfer-community`.

## Contexto del device

- pmOS edge vivo, kernel `6.16.4` vendored (`mt6785-mainline/linux` fork), systemd.
- **UFS** `59.6G` = `/dev/sdc` (47 particiones GPT; `sdc46` = userdata 52.3G), microSD `mmcblk0` 29G, zram swap.
- Rootfs montado en loop: `/dev/loop0` = `/dev/sdc46` (sector 4096), `loop0p1` = `/boot` (ext2, 480M),
  `loop0p2` = `/` (ext4, 51.8G). — Esquema idéntico al de Kupfer (imagen `msdos`: p1 boot + p2 root
  dentro de `userdata`).
- **deviceinfo** (de pmaports): header_version 2, dtb `mediatek/mt6785-xiaomi-begonia.dtb`,
  `recovery_dtbo /boot/empty.dtbo`, offsets base 0x40078000 / kernel 0x8000 / ramdisk 0x07c08000 /
  second 0xbff88000 / tags 0x0bc08000 / dtb 0x0bc08000, pagesize 2048, `rootfs_image_sector_size=4096`.
- Kernel cmdline obligatoria: `bootopt=64S3,32N2,64N2`.
- Táctil: variante **Tianma** ya confirmada en pmOS 6.16.4 vía **swap de firmware**
  (`nt36672a_begonia_tianma.bin.zst` bajo el nombre csot) — ver commit del port.
- WiFi/BT SoC: precisa rebuild con rama `begonia-conn-wifi`.

## Dependencias del port (rama `dev`)

PKGBUILDs nuevos (repos de Kupfer):

| PKGBUILD | Repo | Notas |
|---|---|---|
| `device/device-mt6785-xiaomi-begonia` | `device/` | cargo del deviceinfo pmOS a commit fijo |
| `linux/linux-mt6785` | `linux/` | kernel `mt6785-mainline/linux`, Image.gz + dtbs |
| `firmware/firmware-mediatek-mt6785` | `firmware/` | blobs conectividad MTK + novatek + rtl |

Sobre el parche a `boot/boot-android-bootimg-updater`: **ya no hace falta.** Se escribió cuando la
base era `main`, que generaba header v0 con el DTB concatenado. Al cambiar a `dev` se comprobó que
`dev` ya trae el branching por `header_version` y el soporte de `--recovery_dtbo`, y que el
`update-bootimg.sh` de nuestro overlay es **byte a byte idéntico** al de `dev` @ `3df1d56`. Se deja
el overlay igualmente, como copia de seguridad: si upstream lo revierte, el port no se rompe en
silencio.

### Gaps detectados (todo el detalle en `docs/PORT.md`)

1. Begonia exige **header v2** (DTB separado + `--recovery_dtbo /boot/empty.dtbo`).
   `dev` sí trae el branching por `header_version` en `update-bootimg.sh`, pero **no soporta
   `--recovery_dtbo` en absoluto** (0 coincidencias de `dtbo` en todo el repo). Hace falta parche,
   y además hace falta el fichero `empty.dtbo`. Ver "El overlay del boot updater" más abajo.
2. Kernel cmdline `bootopt=64S3,32N2,64N2` → `deviceinfo_kernel_cmdline`.
3. DTB path → `deviceinfo_dtb="mediatek/mt6785-xiaomi-begonia"`.
4. Módulos de display/táctil en initramfs real → `mkinitcpio.conf.d` del device
   (`lm36274_bl, lm363x-regulator, novatek-nvt-ts-spi, panel-novatek-nt36672a, ti-lmu`).
5. `vbmeta` (flags=2) + `erase dtbo`: Kupfer no los flashea — pasos fastboot manuales extra.
6. Primer SoC MTK: no hay stack modem (igual que pmOS mainline, sin modem funcional).
7. Firmwares: `mediatek/` conectividad (7 blobs), `novatek/nt36672a_begonia_tianma.bin`, y
   `rtl_bt/rtl8821c_*` + `rtlwifi/rtl8192eu_nic.bin` para los dongles del hub.
8. **WiFi interno MediaTek (gen4m) desactivado a propósito.** `wlan_gen4m.ko` llama a
   `wireless_send_event()`, que solo se compila con `CONFIG_WEXT_CORE`; sin esa opción
   modpost aborta el kernel con `ERROR: modpost: "wireless_send_event" [...] undefined!`.
   El WiFi del hub (`rtl8xxxu`, `mt76`) no depende de ese stack, así que la imagen no debe
   depender de él. Ver `overlay/linux-mt6785/extra_config` para reactivarlo.
   Comprobado: con `CONFIG_WEXT_CORE=y` el símbolo resuelve y el kernel compila entero.

### El overlay del boot updater: dos trampas, y ninguna era visible

Sin esto begonia no arranca, y los dos fallos son silenciosos por construcción:

**a) La ruta del overlay estaba mal.** `cp -r src dst/` crea `dst/<basename de src>`. Con el
directorio del overlay llamado `boot-android-bootimg-updater` el fichero aterrizaba en
`boot/boot-android-bootimg-updater/`, una ruta que kupferbootstrap no conoce. El overlay
*parecía* aplicado y no lo estaba. Renombrado a `boot/android-bootimg-updater`, que es como se
llama en `kupfer/packages/pkgbuilds`, donde el `cp` fusiona encima del paquete real (y conserva
el `.hook` y el `.install` de upstream).

**b) El prebuilt le ganaba.** `boot-android-bootimg-updater` no está en `BASE_LOCAL_PACKAGES`
ni en la lista de `cmd_build`: llega por `--syncdeps`. `image build` pasa `try_download=True` a
`check_package_version_built()`, que compara `pkgver-pkgrel` contra disco/repo y, si no está,
**descarga el prebuilt** `boot-android-bootimg-updater-0.5-1-aarch64.pkg.tar.xz` de
`prebuilts/…/aarch64/boot/`. Descargado y verificado: su `update-bootimg` **no** trae el
`--recovery_dtbo`. El overlay nunca se construía.

Solución: subir `pkgrel` a `2` en el PKGBUILD overlaid. El nombre deja de coincidir con el del
prebuilt, así que se construye localmente. El paso de overlays verifica además que el
`pkgrel=2` sigue ahí, que el script contiene `recovery_dtbo`, y que el `empty.dtbo` tiene el
sha256 esperado — porque un overlay que se pierde en silencio no falla, y es exactamente lo que
pasó.

### `empty.dtbo`: por qué va versionado y no se genera

El bootloader de begonia arranca con header v2 y sin un recovery dtbo vacío no localiza el dtbo
de recovery. pmaports lo resuelve generando el dtbo en su APKBUILD con
`mkdtboimg create`, que viene del subpackage de Alpine `android-tools-mkdtboimg`. En Arch no
existe `mkdtboimg` ni en los repos ni en la AUR, y el prebuilt de Kupfer `mkbootimg-git-r254…`
solo trae `mkbootimg` y `unpack_bootimg`. `mkbootimg` sí acepta `--recovery_dtbo <path>`; lo que
faltaba era el fichero.

Así que el binario de 136 bytes va versionado en el overlay del device. Es el que genera
pmaports, con el magic **MediaTek** `0xd7b7ab1e` (AOSP usa `0xd7b7caf1`) — de ahí que se
reutilicen los bytes exactos en vez de reinventar el formato. Se regenera con:

```sh
echo '/dts-v1/; / {};' | dtc -I dts -O dtb -o empty.dtb
mkdtboimg create empty.dtbo empty.dtb   # -> 136 bytes, sha256 f72e1df5…
```

## Notas de CI

- El build usa el wrapper **Docker** de kupferbootstrap (`type = "docker"`): construye
  Arch packages con `makepkg`, que no existe en el runner Ubuntu (`type = "none"` →
  `makepkg: command not found`).
- `DOCKER_BUILDKIT=1` es obligatorio: el `Dockerfile` upstream usa `RUN --mount=type=bind`
  y `ADD --link`, que requieren BuildKit.
- `registry.gitlab.com/kupfer/kupferbootstrap` **no es pullable anónimamente** (302 → sign_in), así
  que el workflow construye la imagen antes de usarla. Eso calienta además las capas en la cache
  de BuildKit.
- Las invocaciones van envueltas en `script -qec` porque el wrapper hace `docker run -it`
  y los runners de Actions no tienen TTY (`the input device is not a TTY`).
- El TOML se valida contra el esquema de kupferbootstrap **antes** de arrancar el build, y con un
  chequeo de tipos extra: `Config.fromDict(validate=True)` no distingue `True` de `1` porque en
  Python `True` es un `int` válido, y ese agujero dejó pasar dos bugs de tipo seguidos
  (`clean_mode` como string, `parallel_downloads` como bool) que rompieron más tarde, dentro de
  pacman, con `invalid value for 'ParallelDownloads' : 'True'`.

## Artefactos del build

- `aboot.img` → boot partition (`fastboot flash boot`)
- `image full` → `fastboot flash userdata` (sparse)

## Flasheo (tras build GHA exitoso)

```sh
# 1. Backup de la imagen pmOS actual (rollback)
# 2. En fastboot:
fastboot flash boot aboot.img
fastboot flash userdata begonia-kupfer.img   # sparse
fastboot flash vbmeta vbmeta.img             # flags=2
fastboot erase dtbo
fastboot reboot
```

> Kupfer no gestiona vbmeta/dtbo: los pasos extra son obligatorios y estándar en begonia.
> `vbmeta.img` = `avbtool make_vbmeta_image --flags 2 --padding_size 2048`.

## Build en GitHub Actions

Ver `.github/workflows/build.yaml` + `docs/CI.md`. Runs bajo demanda (`workflow_dispatch`).
Los builds pesados van a GHA (evita OOM en la máquina local).

## Roadmap

- [ ] Port PKGBUILDs y overlay de boot-img (rama `begonia` del fork pkgbuilds)
- [ ] Build imagen Plasma Mobile en GHA (base `dev`)
- [ ] Flasheo + verificación (panel Tianma, touch, WiFi/Bluetooth dongles, Plasma)
- [ ] MR upstream a `kupfer/packages/pkgbuilds` (rama `dev`) — **con informe de qué funciona, qué
      no, y qué no se probó**, que es lo que pide la contribución
- [ ] Replicar método táctil tianma (pmOS) documentado

## Referencias

- https://kupfer.gitlab.io / https://gitlab.com/kupfer/kupferbootstrap
- https://gitlab.com/kupfer/packages/pkgbuilds
- pmOS begonia: `pmaports/device/testing/device-xiaomi-begonia`
- MR Dinolek "begonia tianma": pmaports MR !8852 (kernel 7.1 + split CSOT/Tianma)
- Fork kernel: `https://gitlab.postmarketos.org/minorum/linux` @ `3a1ea769` (begonia-conn-wifi)
- Fork firmware: `mt6785-mainline/firmware` @ `33aa9fe1` (conectividad)