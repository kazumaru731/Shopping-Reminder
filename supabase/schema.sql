-- 1. テーブル定義

-- プロフィール
create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  display_name text,
  avatar_url text,
  updated_at timestamptz default now()
);

-- 買い物リスト
create table public.lists (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  owner_id uuid references public.profiles(id) on delete cascade not null,
  created_at timestamptz default now()
);

-- リストメンバー (多対多)
create table public.list_members (
  list_id uuid references public.lists(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  role text default 'member' check (role in ('owner', 'member')),
  primary key (list_id, user_id)
);

-- 買い物項目
create table public.items (
  id uuid default gen_random_uuid() primary key,
  list_id uuid references public.lists(id) on delete cascade not null,
  name text not null,
  due_date timestamptz,
  is_purchased boolean default false,
  purchaser_id uuid references public.profiles(id),
  planning_purchaser_id uuid references public.profiles(id),
  notification_interval jsonb default '{"type": "none"}'::jsonb,
  created_at timestamptz default now()
);

-- 個人用通知設定 (オーバーライド)
create table public.personal_notification_settings (
  item_id uuid references public.items(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  is_muted boolean default false,
  custom_time time,
  primary key (item_id, user_id)
);

-- 2. Row Level Security (RLS) 設定

alter table public.profiles enable row level security;
alter table public.lists enable row level security;
alter table public.list_members enable row level security;
alter table public.items enable row level security;
alter table public.personal_notification_settings enable row level security;

-- Profiles: 自分のプロフィールは編集可能、他人は閲覧のみ
create policy "Public profiles are viewable by everyone." on public.profiles for select using (true);
create policy "Users can update own profile." on public.profiles for update using (auth.uid() = id);

-- Lists: メンバーであるリストのみ閲覧・編集可能
create policy "Members can view lists." on public.lists for select
  using (exists (select 1 from public.list_members where list_id = lists.id and user_id = auth.uid()));

create policy "Owners can update lists." on public.lists for update
  using (owner_id = auth.uid());

-- List Members: リストのメンバーであれば一覧を確認可能
create policy "Members can view other members." on public.list_members for select
  using (exists (select 1 from public.list_members lm where lm.list_id = list_members.list_id and lm.user_id = auth.uid()));

-- Items: リストのメンバーであれば操作可能
create policy "Members can view items." on public.items for select
  using (exists (select 1 from public.list_members where list_id = items.list_id and user_id = auth.uid()));

create policy "Members can insert items." on public.items for insert
  with check (exists (select 1 from public.list_members where list_id = items.list_id and user_id = auth.uid()));

create policy "Members can update items." on public.items for update
  using (exists (select 1 from public.list_members where list_id = items.list_id and user_id = auth.uid()));

-- 3. 自動プロフィール作成用トリガー (Auth 連携)
create function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data->>'display_name');
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
