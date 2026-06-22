-- Add covering indexes for foreign keys reported by Supabase Performance Advisor.
-- Composite primary keys already cover their leading columns, so this migration
-- only adds indexes for FK columns that are not covered by an existing index prefix.

create index if not exists idx_group_members_user_id
  on public.group_members (user_id);

create index if not exists idx_groups_owner_id
  on public.groups (owner_id);

create index if not exists idx_items_creator_id
  on public.items (creator_id);

create index if not exists idx_items_list_id
  on public.items (list_id);

create index if not exists idx_items_planning_purchaser_id
  on public.items (planning_purchaser_id);

create index if not exists idx_items_purchaser_id
  on public.items (purchaser_id);

create index if not exists idx_list_members_user_id
  on public.list_members (user_id);

create index if not exists idx_lists_group_id
  on public.lists (group_id);

create index if not exists idx_lists_owner_id
  on public.lists (owner_id);

create index if not exists idx_personal_notification_settings_user_id
  on public.personal_notification_settings (user_id);
