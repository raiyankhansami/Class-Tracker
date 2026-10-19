# Class Tracker

A small, responsive website for 3–5 students with private individual calendars, a separate admin login, generated student UIDs, and admin-controlled green tick marks.

## What is included

- `index.html` — the website UI and application logic.
- `config.js` — public Supabase project settings and optional social links.
- `supabase_schema.sql` — database tables, account profile/UID creation, and row-level security policies.

## Security model

- Students sign in with a verified Bangladesh phone number and a one-time SMS code.
- Students can read only their own profile and calendar marks.
- Students cannot add or remove calendar marks.
- The admin signs in separately using email and password.
- Only the account explicitly listed in `app_admins` can view all student profiles and add/remove marks.
- No Supabase service-role/secret key belongs in the website. The browser uses only the public anon/publishable key.

## Setup the real service

### 1. Create Supabase project

1. Create a project at <https://supabase.com>.
2. Open **SQL Editor**, create a new query, paste all of `supabase_schema.sql`, and run it.
3. Open **Project Settings → API** (or **Connect**, depending on the dashboard version). Copy your Project URL and public anon/publishable key.
4. Edit `config.js` and replace the two placeholders:

```js
window.CLASS_TRACKER_CONFIG = {
  supabaseUrl: "https://YOUR_PROJECT.supabase.co",
  supabaseAnonKey: "YOUR_PUBLIC_ANON_OR_PUBLISHABLE_KEY",
  whatsappUrl: "",
  facebookUrl: ""
};
```

Use the project's public anon/publishable key only. **Never use `service_role`, a secret key, or a database password in `config.js`.**

### 2. Enable phone OTP for students

1. In Supabase, open **Authentication → Providers** and enable **Phone**.
2. Configure an SMS provider supported by Supabase and add its credentials. Phone login will not send real SMS until this is configured.
3. Set the OTP length/expiry and rate limits to sensible values. Enable CAPTCHA/rate limiting for a public deployment if available in your Supabase Auth settings.
4. Test with a phone number you control. Depending on your SMS provider, SMS charges may apply.

Students use the **Student login** tab. The first verified phone login creates a profile and unique ID like `CT-A1B2C3D4`; later logins use the same phone. A student needs a verified account/session to see their data.

### 3. Create your separate admin login

1. Go to **Authentication → Users** and create an Auth user for the administrator with an email and a strong password. Use your own email address; do not expose the password publicly.
2. In the SQL Editor, replace `YOUR_ADMIN_EMAIL@example.com` in the two commented SQL statements at the bottom of `supabase_schema.sql` with the exact email you used.
3. Uncomment and run both statements (or run these with your real email substituted):

```sql
insert into public.app_admins (user_id)
select id from auth.users where lower(email) = lower('YOUR_ADMIN_EMAIL@example.com')
on conflict (user_id) do nothing;

update public.profiles
set role = 'admin'
where id = (select id from auth.users where lower(email) = lower('YOUR_ADMIN_EMAIL@example.com'));
```

4. Sign in through **Admin login** using that email/password. There is no public admin registration form.

The admin account must exist in `app_admins`; setting only the profile role is not enough to obtain database permissions. This is intentional.

### 4. Run it locally

On Windows, double-click `run_local.bat`; it starts a local server and opens the page. Or from this directory, start a local static server manually (opening the HTML as a `file://` URL may block module imports):

```bash
python -m http.server 8080
```

Open <http://localhost:8080> in a browser.

### 5. Publish the website

Upload the contents of this folder (`index.html`, `config.js`, and `supabase_schema.sql`/`README.md`) to a static host such as Netlify, Cloudflare Pages, or Vercel. `index.html` is the entry point. For Netlify, you can deploy the folder as a static site; for Vercel/Cloudflare Pages, use the static/other framework preset as applicable.

After deploying, add your production website URL to the Supabase **Authentication → URL Configuration → Site URL / Redirect URLs** when prompted by the project configuration. Keep the exact deployed origin in the allowed redirect URLs if your Auth configuration uses redirects.

### 6. Add your WhatsApp and Facebook links

Edit `config.js`:

```js
whatsappUrl: "https://wa.me/8801864939198",
facebookUrl: "https://www.facebook.com/YOUR_PAGE_OR_PROFILE"
```

Leave either value as an empty string until you are ready; the footer will show the social option and explain that a link has not been added yet.

## Notes before public launch

- This source code is prepared to connect to a Supabase project, but it is not already hosted and it is not connected to a Supabase project because project credentials and an admin Auth account must be created by the owner.
- Test with two separate student phone accounts: each should see only their own calendar; neither should be able to mark a date or read another profile by changing browser requests.
- Test that the administrator can select each student, add a green tick, remove it, and see it after reloading.
- Supabase RLS is the security boundary. Do not remove the policies or put a secret/service-role key into browser code.
