# Forum board favorite is a native authenticated write

**Forum Board Favorite** will be implemented as a native authenticated Yamibo request using the current `SessionState` and a `formhash` parsed from forum HTML. If the required authentication or form hash is unavailable, the **Native Forum Surface** shows a login or refresh error instead of silently falling back to WebView; posting new threads remains a **Forum Web Fallback** flow.
