-- Harden client-facing data access and remove high-privilege secrets from
-- database trigger definitions.

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

grant usage on schema private to authenticated;
grant usage on schema private to service_role;

create or replace function private.is_group_member(_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members gm
    where gm.group_id = _group_id
      and gm.user_id = (select auth.uid())
  );
$$;

create or replace function private.is_group_owner(_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.groups g
    where g.id = _group_id
      and g.owner_id = (select auth.uid())
  );
$$;

create or replace function private.can_access_list(_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.lists l
    where l.id = _list_id
      and (
        l.owner_id = (select auth.uid())
        or private.is_group_member(l.group_id)
      )
  );
$$;

create or replace function private.is_list_owner(_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.lists l
    where l.id = _list_id
      and l.owner_id = (select auth.uid())
  );
$$;

create or replace function private.can_access_item(_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.items i
    where i.id = _item_id
      and private.can_access_list(i.list_id)
  );
$$;

create or replace function private.can_view_profile(_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    _profile_id = (select auth.uid())
    or exists (
      select 1
      from public.group_members viewer
      join public.group_members target
        on target.group_id = viewer.group_id
      where viewer.user_id = (select auth.uid())
        and target.user_id = _profile_id
    );
$$;

grant execute on function private.is_group_member(uuid) to authenticated;
grant execute on function private.is_group_owner(uuid) to authenticated;
grant execute on function private.can_access_list(uuid) to authenticated;
grant execute on function private.is_list_owner(uuid) to authenticated;
grant execute on function private.can_access_item(uuid) to authenticated;
grant execute on function private.can_view_profile(uuid) to authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data->>'display_name');
  return new;
end;
$$;

create or replace function public.delete_empty_group()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.group_members gm
    where gm.group_id = old.group_id
  ) then
    delete from public.groups g
    where g.id = old.group_id;
  end if;

  return old;
end;
$$;

drop trigger if exists trigger_delete_empty_group on public.group_members;
create trigger trigger_delete_empty_group
after delete on public.group_members
for each row
execute function public.delete_empty_group();

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
begin
  target_user_id := auth.uid();

  if target_user_id is null then
    raise exception 'Authentication is required.';
  end if;

  delete from public.push_tokens
  where user_id = target_user_id;

  delete from public.group_members
  where user_id = target_user_id;

  delete from public.profiles
  where id = target_user_id;

  delete from auth.users
  where id = target_user_id;
end;
$$;

create or replace function public.find_group_for_join(search_code text)
returns setof public.groups
language sql
stable
security definer
set search_path = ''
as $$
  select g.*
  from public.groups g
  where (select auth.uid()) is not null
    and (
      g.invite_code = upper(trim(search_code))
      or g.id::text = trim(search_code)
    )
  limit 1;
$$;

revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;
revoke execute on all functions in schema public from authenticated;

grant execute on function public.delete_own_account() to authenticated;
grant execute on function public.find_group_for_join(text) to authenticated;

drop policy if exists "members_access" on public.group_members;
drop policy if exists "Allow select for authenticated users" on public.groups;
drop policy if exists "groups_access" on public.groups;
drop policy if exists "Item access" on public.items;
drop policy if exists "Members can insert items." on public.items;
drop policy if exists "Members can update items." on public.items;
drop policy if exists "items_access" on public.items;
drop policy if exists "Member access" on public.list_members;
drop policy if exists "List access" on public.lists;
drop policy if exists "lists_access" on public.lists;
drop policy if exists "Public profiles are viewable by everyone." on public.profiles;
drop policy if exists "Users can update own profile." on public.profiles;
drop policy if exists "Users can manage their own tokens" on public.push_tokens;

create policy "profiles_select_visible"
on public.profiles
for select
to authenticated
using (private.can_view_profile(id));

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy "groups_select_member"
on public.groups
for select
to authenticated
using (owner_id = (select auth.uid()) or private.is_group_member(id));

create policy "groups_insert_owner"
on public.groups
for insert
to authenticated
with check (owner_id = (select auth.uid()));

create policy "groups_update_owner"
on public.groups
for update
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy "groups_delete_owner"
on public.groups
for delete
to authenticated
using (owner_id = (select auth.uid()));

create policy "group_members_select_group"
on public.group_members
for select
to authenticated
using (user_id = (select auth.uid()) or private.is_group_member(group_id));

create policy "group_members_insert_self"
on public.group_members
for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy "group_members_update_owner"
on public.group_members
for update
to authenticated
using (private.is_group_owner(group_id))
with check (private.is_group_owner(group_id));

create policy "group_members_delete_self_or_owner"
on public.group_members
for delete
to authenticated
using (user_id = (select auth.uid()) or private.is_group_owner(group_id));

create policy "lists_select_member"
on public.lists
for select
to authenticated
using (owner_id = (select auth.uid()) or private.is_group_member(group_id));

create policy "lists_insert_member"
on public.lists
for insert
to authenticated
with check (
  owner_id = (select auth.uid())
  and private.is_group_member(group_id)
);

create policy "lists_update_owner_or_editable_member"
on public.lists
for update
to authenticated
using (
  owner_id = (select auth.uid())
  or (coalesce(allow_member_edit, false) and private.is_group_member(group_id))
)
with check (
  owner_id = (select auth.uid())
  or private.is_group_member(group_id)
);

create policy "lists_delete_owner"
on public.lists
for delete
to authenticated
using (owner_id = (select auth.uid()));

create policy "list_members_select_list"
on public.list_members
for select
to authenticated
using (user_id = (select auth.uid()) or private.can_access_list(list_id));

create policy "list_members_insert_self"
on public.list_members
for insert
to authenticated
with check (user_id = (select auth.uid()) and private.can_access_list(list_id));

create policy "list_members_update_owner"
on public.list_members
for update
to authenticated
using (private.is_list_owner(list_id))
with check (private.is_list_owner(list_id));

create policy "list_members_delete_self_or_owner"
on public.list_members
for delete
to authenticated
using (user_id = (select auth.uid()) or private.is_list_owner(list_id));

create policy "items_select_list_member"
on public.items
for select
to authenticated
using (private.can_access_list(list_id));

create policy "items_insert_list_member"
on public.items
for insert
to authenticated
with check (
  private.can_access_list(list_id)
  and (creator_id is null or creator_id = (select auth.uid()))
);

create policy "items_update_list_member"
on public.items
for update
to authenticated
using (private.can_access_list(list_id))
with check (private.can_access_list(list_id));

create policy "items_delete_creator_or_editable"
on public.items
for delete
to authenticated
using (
  private.can_access_list(list_id)
  and (
    creator_id = (select auth.uid())
    or coalesce(allow_collaborator_edit, false)
    or private.is_list_owner(list_id)
  )
);

create policy "personal_notification_settings_select_own"
on public.personal_notification_settings
for select
to authenticated
using (user_id = (select auth.uid()));

create policy "personal_notification_settings_insert_own"
on public.personal_notification_settings
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and private.can_access_item(item_id)
);

create policy "personal_notification_settings_update_own"
on public.personal_notification_settings
for update
to authenticated
using (user_id = (select auth.uid()))
with check (
  user_id = (select auth.uid())
  and private.can_access_item(item_id)
);

create policy "personal_notification_settings_delete_own"
on public.personal_notification_settings
for delete
to authenticated
using (user_id = (select auth.uid()));

create policy "push_tokens_select_own"
on public.push_tokens
for select
to authenticated
using (user_id = (select auth.uid()));

create policy "push_tokens_insert_own"
on public.push_tokens
for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy "push_tokens_update_own"
on public.push_tokens
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy "push_tokens_delete_own"
on public.push_tokens
for delete
to authenticated
using (user_id = (select auth.uid()));

revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;

grant select, insert, update, delete on public.groups to authenticated;
grant select, insert, update, delete on public.group_members to authenticated;
grant select, insert, update, delete on public.lists to authenticated;
grant select, insert, update, delete on public.list_members to authenticated;
grant select, insert, update, delete on public.items to authenticated;
grant select, insert, update, delete on public.personal_notification_settings to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.push_tokens to authenticated;

revoke update on public.groups from authenticated;
grant update (name, allow_member_edit) on public.groups to authenticated;

revoke update on public.group_members from authenticated;
grant update (role) on public.group_members to authenticated;

revoke update on public.lists from authenticated;
grant update (
  name,
  reminder_interval,
  reminder_targets,
  allow_member_edit,
  notes
) on public.lists to authenticated;

revoke update on public.list_members from authenticated;
grant update (role) on public.list_members to authenticated;

revoke update on public.items from authenticated;
grant update (
  name,
  due_date,
  is_purchased,
  purchaser_id,
  planning_purchaser_id,
  reminder_interval,
  reminder_targets,
  link_url,
  image_url,
  allow_collaborator_edit,
  notes
) on public.items to authenticated;

revoke update on public.personal_notification_settings from authenticated;
grant update (is_muted, custom_time) on public.personal_notification_settings to authenticated;

revoke update on public.profiles from authenticated;
grant update (
  display_name,
  avatar_url,
  notify_on_list_delete,
  notify_on_item_delete,
  notify_on_group_leave
) on public.profiles to authenticated;

revoke update on public.push_tokens from authenticated;
grant update (token, device_id) on public.push_tokens to authenticated;

grant all privileges on all tables in schema public to service_role;

alter table public.group_members enable row level security;
alter table public.groups enable row level security;
alter table public.items enable row level security;
alter table public.list_members enable row level security;
alter table public.lists enable row level security;
alter table public.personal_notification_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.push_tokens enable row level security;

drop policy if exists "Authenticated users can upload" on storage.objects;
drop policy if exists "Public Access" on storage.objects;

create policy "item_images_insert_own_folder"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'item-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and lower(storage.extension(name)) in ('jpg', 'jpeg')
);

create policy "item_images_select_own_folder"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'item-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "item_images_delete_own_folder"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'item-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create or replace function private.invoke_notification_webhook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
  payload jsonb;
begin
  select decrypted_secret
  into webhook_secret
  from vault.decrypted_secrets
  where name = 'notification_webhook_secret'
  limit 1;

  if webhook_secret is null then
    raise warning 'notification webhook secret is missing';
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  payload := jsonb_build_object(
    'type', tg_op,
    'table', tg_table_name,
    'record', case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    'old_record', case when tg_op = 'INSERT' then null else to_jsonb(old) end
  );

  perform net.http_post(
    url := 'https://xhzvkjokpvrdwbiebitb.supabase.co/functions/v1/send-item-notification',
    body := payload,
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', webhook_secret
    ),
    timeout_milliseconds := 5000
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists send_push_notification on public.items;
drop trigger if exists send_list_notification on public.lists;
drop trigger if exists send_group_notification on public.group_members;

create trigger send_push_notification
after insert or update or delete on public.items
for each row
execute function private.invoke_notification_webhook();

create trigger send_list_notification
after insert or delete on public.lists
for each row
execute function private.invoke_notification_webhook();

create trigger send_group_notification
after insert or delete on public.group_members
for each row
execute function private.invoke_notification_webhook();

drop function if exists public.check_is_member(uuid);
drop function if exists public.is_list_member(uuid);

alter default privileges in schema public
  revoke execute on functions from public;
alter default privileges in schema public
  revoke execute on functions from anon, authenticated;
alter default privileges in schema public
  revoke select, insert, update, delete on tables from anon, authenticated;
alter default privileges in schema public
  revoke usage, select on sequences from anon, authenticated;
