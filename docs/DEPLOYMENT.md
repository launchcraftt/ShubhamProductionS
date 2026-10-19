# Deployment to Vercel

1. Commit the existing site and the new portal files to your repository.
2. Keep the existing Vercel project/build settings. This codebase is a static HTML site and does not need a Node build command for the portal.
3. Configure Supabase URL and public anon/publishable key in `portal.js`, commit only those public client values, and redeploy. The anon key is designed for browser use; RLS must be correct. Never include a service-role key.
4. In Supabase Authentication → URL Configuration, set the production website URL as the Site URL and add the exact deployed portal URL to Redirect URLs for magic-link authentication.
5. Apply the SQL migration and create the first admin account using `docs/DATABASE_SETUP.md`.
6. Invite a test client account and verify that it can see only its own project. Verify a second unrelated account cannot read project rows or private Storage objects.
7. Test a project with non-sensitive test images before adding real client galleries.

The code changes do not deploy themselves; deploy through the existing Vercel project after reviewing the diff.
