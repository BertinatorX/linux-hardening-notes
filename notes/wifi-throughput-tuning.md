# Wi-Fi Throughput Tuning Notes

## Goal

Write down the wireless troubleshooting process I used to improve throughput on my Linux workstation.

## Hardware

- Adapter: Alfa Wi-Fi 6E adapter
- Chipset: MediaTek MT7921AU
- Bands tested: 2.4GHz and 5GHz

## Symptoms

Initial observed throughput was much lower than it should have been for this adapter and this network.

## Variables reviewed

- Wireless power-save settings
- TCP congestion control algorithm
- Wireless band selection
- USB port selection
- Driver behavior
- Physical connection quality

## Commands and checks

Check wireless device:

```bash
iw dev
```

Check link quality:

```bash
iw dev wlan0 link
```

Check IP address and route:

```bash
ip addr
ip route
```

Check current TCP congestion control:

```bash
sysctl net.ipv4.tcp_congestion_control
```

Set BBR temporarily:

```bash
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
```

Check USB devices:

```bash
lsusb
```

## Findings

- Initial throughput was around 230 Mbps.
- After tuning and testing, throughput got up to around 900 Mbps under the conditions I tested.
- The USB port was the big one, some ports gave much lower throughput than others.
- Band selection mattered too, since this environment has both 2.4GHz and 5GHz available.

## Verification

I called it good after repeated throughput tests kept showing the higher numbers and the connection stayed stable.

## What I learned

Test more than one layer when troubleshooting a network. A slow connection isn't always the ISP or the router, the adapter driver, power-save settings, TCP settings, the wireless band, and the physical USB port can all affect performance.
