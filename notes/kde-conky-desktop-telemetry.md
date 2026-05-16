# KDE and Conky Desktop Telemetry

## Goal

Document desktop configuration work used to display useful system telemetry on a KDE Plasma workstation.

## Tools

- KDE Plasma
- KWin compositor
- Kvantum theme engine
- Conky
- Zsh

## Why this matters

Desktop customization can be support-relevant when it involves repeatable configuration, startup troubleshooting, monitoring, and documentation.

## Conky configuration example

```lua
conky.config = {
  gap_x = 40,
  gap_y = 40,
  minimum_width = 350,
  net_avg_samples = 2,
  own_window = true,
  own_window_class = 'Conky',
  own_window_type = 'desktop',
  own_window_argb_visual = true,
  own_window_argb_value = 0,
  update_interval = 1.0,
  use_xft = true,
}
```

## Startup issue

Conky could start before the compositor was fully ready, causing transparency or display issues.

## Resolution

Added a startup delay so the compositor initializes before Conky loads.

## Verification

The overlay displayed system uptime, CPU load, memory usage, wireless signal, gateway status, and storage usage after login.

## What I learned

Even visual configuration requires troubleshooting discipline. Startup timing, compositor behavior, theme engines, and display settings can interact in ways that require testing and documentation.
