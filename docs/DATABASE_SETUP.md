# Database setup

## Apply the migration

In the Supabase Dashboard, open **SQL Editor**, create a new query, paste the full contents of `supabase/migrations/202610190001_client_portal.sql`, and run it against the intended project. Alternatively, after linking the Supabase CLI to your project, use `supabase db push` from the repository root.

The migration creates profiles, projects, project members, events, photos, favourites, album selections, payments, project activity, delivery items, RLS policies, helper functions and the private `private-gallery` bucket.

## Create the first administrator securely

1. In Supabase Dashboard → Authentication → Users, create/invite the photographer's own account. Use an email you control.
2. Sign in to the portal once so the profile trigger creates the profile row.
3. In SQL Editor, run the following with the actual account email:

```sql
update public.profiles
set role = 'admin'
where lower(email) = lower('YOUR-ADMIN-EMAIL@example.com');
```

Never expose a service-role key or use a shared hardcoded password. Keep admin account MFA enabled where available.

## Client access

Create/invite the client in Supabase Authentication before linking them to a project. Their authenticated email must match `projects.client_email`. The project creation UI attempts to link an already registered client; it cannot send invitations because that requires a trusted server-side admin integration. If linking fails, use the Supabase dashboard to invite the client and retry the link flow after they have a profile.

## Data model

- `profiles` maps Supabase Auth users to roles.
- `projects` stores project, selection limit, delivery and gallery settings.
- `project_members` grants project-specific access.
- `events` groups a project's photos.
- `photos` stores metadata and private storage keys, not binary files.
- `favorites` stores each user's favourites.
- `album_selections` stores draft/submitted selections and timestamps.
- `payments` stores manual payment tracking; it does not process payments.
- `project_activity` and `delivery_items` provide an audit/delivery foundation.

All project data tables have RLS enabled. Review and test policies in a staging project before adding real client data. SQL migrations are intended to be applied once to a fresh project; do not blindly re-run `CREATE POLICY` statements on an already migrated database.
