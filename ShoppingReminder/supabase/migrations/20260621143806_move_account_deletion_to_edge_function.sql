-- Move privileged account deletion out of the exposed API schema and make
-- profile deletion resilient when items still reference the deleted user.

revoke execute on function public.delete_own_account() from authenticated;
drop function if exists public.delete_own_account();

alter table public.items
  drop constraint if exists items_creator_id_fkey;

alter table public.items
  add constraint items_creator_id_fkey
  foreign key (creator_id)
  references public.profiles(id)
  on delete set null;

alter table public.items
  drop constraint if exists items_purchaser_id_fkey;

alter table public.items
  add constraint items_purchaser_id_fkey
  foreign key (purchaser_id)
  references public.profiles(id)
  on delete set null;

alter table public.items
  drop constraint if exists items_planning_purchaser_id_fkey;

alter table public.items
  add constraint items_planning_purchaser_id_fkey
  foreign key (planning_purchaser_id)
  references public.profiles(id)
  on delete set null;
