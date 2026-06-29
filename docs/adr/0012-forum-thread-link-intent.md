# Forum thread links preserve caller intent

Thread links opened from a **Forum Board** thread list will first resolve through `ThreadOpenResolver` so readable novel and manga threads can enter native readers. Thread URLs sent from reader "open in forum" actions will instead open the **Forum Web Fallback** directly, because that caller is asking for the original forum context such as post location, replies, editing, or other web-only actions.
