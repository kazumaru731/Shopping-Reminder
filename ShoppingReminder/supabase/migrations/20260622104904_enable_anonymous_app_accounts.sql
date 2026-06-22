-- Use Supabase Auth as a session issuer and keep app-level user state in
-- public.profiles without relying on email addresses.

alter table public.profiles
  add column if not exists account_type text not null default 'anonymous';

alter table public.profiles
  drop constraint if exists profiles_account_type_check;

alter table public.profiles
  add constraint profiles_account_type_check
  check (account_type in ('anonymous', 'apple'));

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, account_type)
  values (
    new.id,
    nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
    'anonymous'
  )
  on conflict (id) do update
  set
    display_name = coalesce(excluded.display_name, public.profiles.display_name),
    account_type = coalesce(public.profiles.account_type, 'anonymous');

  return new;
end;
$$;

revoke update on public.profiles from authenticated;
grant update (
  display_name,
  avatar_url,
  notify_on_list_delete,
  notify_on_item_delete,
  notify_on_group_leave
) on public.profiles to authenticated;
