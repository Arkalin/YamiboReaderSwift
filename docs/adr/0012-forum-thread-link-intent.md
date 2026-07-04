# Forum thread links preserve caller intent

Thread links opened from a **Forum Board** thread list will first resolve through `YamiboThreadRouteResolver` so readable novel and manga threads can be classified before the caller chooses a destination. Thread URLs sent from reader "open in forum" actions open **Native Thread Reader** through the same resolver's native-thread intent, preserving original forum context such as post location and replies.
