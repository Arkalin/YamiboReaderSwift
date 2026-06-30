# Forum thread routing returns caller-hosted targets

Forum thread taps route to shared native destinations rather than directly presenting readers or falling back to web by default. **Forum Thread Routing** returns a pure **Thread Route Target** for **Novel Detail**, **Manga Detail**, **Native Thread Reader**, or **Forum Web Fallback**; each caller maps that target into its own navigation stack so Forum, Favorites, User Space, and future entry points can reuse the same routing contract without leaking caller-specific navigation enums into Core.
