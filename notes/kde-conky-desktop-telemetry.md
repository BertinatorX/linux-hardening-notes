# KDE and Conky Desktop Telemetry

## Goal

I wanted useful system telemetry showing on my KDE Plasma workstation, this is the desktop configuration work it took.

## Tools

- KDE Plasma
- KWin compositor
- Kvantum theme engine
- Conky
- Zsh

## Why this matters

I'm not pretending desktop customization is serious support work, but it can matter when it involves repeatable configuration, startup troubleshooting, monitoring, and documentation.

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

Conky could start before the compositor was fully ready, which caused transparency or display issues.

## Resolution

Simple fix, I added a startup delay so the compositor initializes before Conky loads.

## Verification

After login the overlay showed system uptime, CPU load, memory usage, wireless signal, gateway status, and storage usage.

## What I learned

Overall it works fine, but even visual configuration needs troubleshooting discipline, which surprised me. Startup timing, compositor behavior, theme engines, and display settings can interact in ways that need testing and documentation, and without that I'd likely still be guessing.
