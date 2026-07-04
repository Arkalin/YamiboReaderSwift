# Forum thread routing returns caller-hosted targets

Yamibo thread taps route through shared type classification rather than directly presenting readers or falling back to web by default. **Yamibo Thread Routing** returns a pure **Thread Route Target** for novel, manga, regular thread, or web fallback, plus normalized thread payload; each caller maps that target into its own destination so Forum can open detail surfaces while Favorites can open readers without leaking caller-specific navigation enums into Core.
