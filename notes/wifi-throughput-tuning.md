# Wi-Fi Throughput Tuning Notes

## Goal

Document a wireless troubleshooting process used to improve throughput on a Linux workstation.

## Hardware

- Adapter: Alfa Wi-Fi 6E adapter
- Chipset: MediaTek MT7921AU
- Bands tested: 2.4GHz and 5GHz

## Symptoms

Initial observed throughput was much lower than expected for the adapter and network environment.

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

- Initial throughput was approximately 230 Mbps.
- After tuning and testing, observed throughput reached approximately 900 Mbps under tested conditions.
- USB port selection had a major impact, with some ports producing much lower throughput.
- Band selection mattered because the environment exposed both 2.4GHz and 5GHz options.

## Verification

The change was considered successful after repeated throughput tests showed improved performance and the connection remained stable.

## What I learned

Network troubleshooting should test multiple layers. A slow connection is not always an ISP or router issue. Adapter driver behavior, power-saving settings, TCP settings, wireless band, and physical USB port selection can all affect performance.
