# Private photo storage

The SQL migration creates a private Supabase Storage bucket named `private-gallery`, limited to JPEG, PNG and WebP files up to 20 MiB. The browser uploads into a path of `<project-uuid>/<event-uuid>/<random-id>-<filename>`. Storage RLS allows project members to read files and only admins/photographers to upload, update or delete them. The portal requests short-lived signed URLs (5 minutes) for display; original object URLs are not intentionally made public.

The portal validates MIME type and size in the browser, but browser validation alone is not a complete file-content inspection. Before production use, add server-side image decoding, malware/content validation as appropriate, thumbnail generation, and a tested retention/deletion process. Do not put original binaries in database rows.

No R2/S3 credentials are required for this Supabase Storage MVP. If moving originals to R2/S3 later, implement a trusted server endpoint to issue narrowly scoped signed upload/download URLs; do not put storage secret keys in `portal.js`.
