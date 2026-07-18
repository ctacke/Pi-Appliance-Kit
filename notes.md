## starting point

this is the output from a clean raspberry pi Lite OD build

```
$ systemd-analyze
Startup finished in 5.741s (kernel) + 26.218s (userspace) = 31.960s
multi-user.target reached after 19.808s in userspace

$ systemd-analyze blame
9.683s NetworkManager.service
5.689s NetworkManager-wait-online.service
4.433s cloud-init-main.service
2.703s dev-mmcblk0p2.device
1.366s cloud-init-local.service
1.052s rpi-eeprom-update.service
 897ms user@1000.service
 818ms keyboard-setup.service
 759ms systemd-udev-trigger.service
 727ms polkit.service
 683ms ModemManager.service
 639ms systemd-journald.service
 576ms cloud-config.service
 570ms rpi-resize-swap-file.service
 536ms systemd-fsck@dev-disk-by\x2dpartuuid-e424c3c6\x2d01.service
 513ms systemd-udevd.service
 502ms systemd-logind.service
 459ms cloud-final.service
 407ms bluetooth.service
 390ms systemd-hostnamed.service
 387ms dev-mqueue.mount
 385ms sys-kernel-debug.mount
 384ms run-lock.mount
 382ms sys-kernel-tracing.mount
 378ms modprobe@drm.service
 376ms modprobe@fuse.service
 373ms modprobe@configfs.service
 372ms systemd-binfmt.service
 353ms kmod-static-nodes.service
  349ms systemd-zram-setup@zram0.service
 336ms wpa_supplicant.service
 335ms avahi-daemon.service
 333ms ssh.service
 326ms systemd-tmpfiles-setup.service
 326ms systemd-rfkill.service
 319ms systemd-modules-load.service
 318ms systemd-timesyncd.service
 315ms cloud-init-network.service
 314ms e2scrub_reap.service
 306ms sys-fs-fuse-connections.mount
 299ms systemd-remount-fs.service
 290ms sys-kernel-config.mount
 263ms systemd-udev-load-credentials.service
 263ms systemd-sysctl.service
 244ms rpi-setup-loop@var-swap.service
 241ms dbus.service
 240ms systemd-tmpfiles-setup-dev-early.service
 218ms sshswitch.service
 182ms alsa-restore.service
 181ms proc-sys-fs-binfmt_misc.mount
 176ms systemd-random-seed.service
 162ms systemd-tmpfiles-clean.service
 152ms systemd-journal-flush.service
 147ms console-setup.service
 144ms boot-firmware.mount
 133ms dev-zram0.swap
 126ms tmp.mount
 114ms systemd-user-sessions.service
 113ms systemd-tmpfiles-setup-dev.service
 111ms user-runtime-dir@1000.service
  75ms modprobe@efi_pstore.service
  
$ systemd-analyze critical-chain
he time when unit became active or started is printed after the "@" character.
The time the unit took to start is printed after the "+" character.

multi-user.target @19.808s
└─ssh.service @19.472s +333ms
  └─network.target @19.459s
    └─NetworkManager.service @9.774s +9.683s
      └─dbus.service @9.499s +241ms
        └─basic.target @9.460s
          └─sockets.target @9.459s
            └─systemd-hostnamed.socket @9.459s
              └─sysinit.target @9.438s
                └─cloud-init-network.service @9.120s +315ms
                  └─cloud-init-local.service @7.748s +1.366s
                    └─cloud-init-main.service @3.310s +4.433s
                      └─systemd-remount-fs.service @2.930s +299ms
                        └─systemd-journald.socket @2.598s
                          └─-.mount @2.343s
                            └─-.slice @2.343s
```


## manual procedure

the following was done to improve the boot speed

```
sudo apt-get update 

sudo systemctl disable NetworkManager-wait-online.service

sudo apt install dhcpcd5 -y
sudo systemctl enable dhcpcd
sudo apt purge network-manager -y

sudo systemctl disable cloud-init  
sudo systemctl disable cloud-init-local  
sudo systemctl disable cloud-config  
sudo systemctl disable cloud-final
sudo apt purge cloud-init
sudo rm -rf /etc/cloud
sudo rm -rf /var/lib/cloud

sudo systemctl disable ModemManager  
sudo apt purge modemmanager

sudo systemctl disable rpi-eeprom-update

sudo systemctl disable NetworkManager-wait-online
```

## second boot

after the above, a boot shows this improved output

```
pi@raspi:~ $ systemd-analyze
Startup finished in 5.110s (kernel) + 7.378s (userspace) = 12.488s
multi-user.target reached after 7.256s in userspace.

pi@raspi:~ $ systemd-analyze blame
2.349s dev-mmcblk0p2.device
 945ms user@1000.service
 818ms e2scrub_reap.service
 785ms dhcpcd.service
 653ms systemd-udev-trigger.service
 575ms avahi-daemon.service
 532ms rpi-resize-swap-file.service
 530ms systemd-fsck@dev-disk-by\x2dpartuuid-e424c3c6\x2d01.service
 504ms systemd-logind.service
 452ms sys-kernel-tracing.mount
 436ms sys-kernel-debug.mount
 433ms run-lock.mount
 431ms modprobe@fuse.service
 426ms modprobe@efi_pstore.service
 426ms systemd-rfkill.service
 424ms modprobe@drm.service
 423ms modprobe@configfs.service
 422ms dev-mqueue.mount
 420ms keyboard-setup.service
 411ms kmod-static-nodes.service
 409ms systemd-journald.service
 380ms systemd-udevd.service
 365ms systemd-binfmt.service
 356ms systemd-hostnamed.service
 355ms systemd-modules-load.service
 355ms ssh.service
 338ms dbus.service
 331ms systemd-zram-setup@zram0.service
 323ms bluetooth.service
 
$ systemd-analyze critical-chain
multi-user.target @7.256s
└─ssh.service @6.899s +355ms
  └─network.target @6.891s
    └─wpa_supplicant.service @6.639s +249ms
      └─dbus.service @6.024s +338ms
        └─basic.target @5.980s
          └─sockets.target @5.979s
            └─systemd-hostnamed.socket @5.978s
              └─sysinit.target @5.932s
                └─systemd-binfmt.service @5.526s +365ms
                  └─proc-sys-fs-binfmt_misc.mount @5.747s +127ms
                    └─systemd-journald.socket @2.554s
                      └─-.mount @2.298s
                        └─-.slice @2.298s
 
```

### second pass

a second pass of improvements was used to further speed things up

```
sudo systemctl disable e2scrub_reap.service

sudo systemctl disable bluetooth
sudo systemctl disable hciuart
sudo apt purge bluez


sudo nano /boot/firmware/config.txt

# append these at the bottom
[all]
enable_uart=1
dtoverlay=spi0-0cs
dtoverlay=noaudio
dtoverlay=disable-bt
```


```
sudo systemctl disable wpa_supplicant.service
sudo nano /etc/systemd/system/wifi-late.service
```

```
[Unit]  
Description=Late WiFi startup  
After=multi-user.target  
  
[Service]  
Type=oneshot  
ExecStart=/usr/sbin/wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf  
ExecStartPost=/usr/sbin/dhcpcd wlan0  
RemainAfterExit=yes  
  
[Install]  
WantedBy=multi-user.target
```

```
sudo systemctl enable wifi-late.service
```

```
sudo systemctl edit dbus.service
```

```
[Unit]  
DefaultDependencies=no
```

```
sudo systemctl disable ssh.service
sudo nano /etc/systemd/system/ssh-late.service
```

```
[Unit]  
Description=Delayed SSH startup  
After=multi-user.target  
  
[Service]  
Type=oneshot  
ExecStart=/usr/sbin/service ssh start  
RemainAfterExit=yes  
  
[Install]  
WantedBy=multi-user.target
```

```
sudo systemctl enable ssh-late.service
```
