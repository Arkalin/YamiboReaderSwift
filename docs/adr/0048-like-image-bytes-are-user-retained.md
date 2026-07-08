# Like Image Bytes Are User-Retained

Image Like Items capture their image bytes into user-retained storage at like time instead of relying on the transparent image cache, because an excerpt's image is content the user asked to keep -- not regenerable decoration -- and source image hosts decay. The source URL stays in Like Item metadata for jump-back, cross-device re-capture, and WebDAV payloads. Deleting a Like Item deletes its retained bytes.
