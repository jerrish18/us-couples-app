-- Add MP3 dedications to the existing private couple-media bucket.
-- Preserve the current MIME list, size limit and all couple-only access policies.
update storage.buckets
set allowed_mime_types = array_append(allowed_mime_types, 'audio/mpeg')
where id = 'couple-media'
  and allowed_mime_types is not null
  and not ('audio/mpeg' = any(allowed_mime_types));
