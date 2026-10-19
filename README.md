# Shubham Production — Client Portal MVP

This repository is an existing static HTML/CSS/JavaScript photography website. The portal has been added as a separate page so the existing portfolio, service pages, enquiry form, and site styles remain independent.

## What is included

- `client-portal.html`, `portal.css`, `portal.js`: responsive sign-in, admin dashboard, project creation, event folders, private image upload, client gallery, favourites, album selection, submission, CSV export, and payment/delivery tracking.
- `supabase/migrations/202610190001_client_portal.sql`: PostgreSQL schema, row-level security policies, selection-limit guard, private Storage bucket and access policies.
- `docs/`: setup, security and deployment notes.

**Not yet production complete:** email invitations are not sent by the browser app; a client account must first be invited through Supabase Auth. Thumbnail generation, resumable uploads, download UI, real email notifications, automated browser tests, and a dedicated admin reopen workflow test remain follow-up hardening items. Do not represent this MVP as fully production-ready until setup and security checks are completed.

## Quick start

1. Create a Supabase project.
2. Run `supabase/migrations/202610190001_client_portal.sql` in the Supabase SQL Editor.
3. In `portal.js`, set `SUPABASE_URL` and `SUPABASE_ANON_KEY` to your project's URL and publishable/anon key. Never use a service-role key in this file.
4. Deploy the static website to Vercel as before. The portal route is `/client-portal.html`.
5. Create/invite your own user in Supabase Authentication, then promote the profile to admin using the SQL command in `docs/DATABASE_SETUP.md`.
6. Sign in and create a project. Invite the client through Supabase Authentication, then link their account to the project using the admin dashboard's project creation flow (the client's email must match an existing profile).

Static hosting does not run server-side code. The security boundary is Supabase Auth + PostgreSQL RLS + private Storage policies.
