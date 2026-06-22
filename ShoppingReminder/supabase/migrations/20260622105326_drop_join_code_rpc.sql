-- The app now resolves join codes through an Edge Function that validates the
-- user's JWT, so the exposed SECURITY DEFINER RPC is no longer needed.

revoke execute on function public.find_group_for_join(text) from authenticated;
drop function if exists public.find_group_for_join(text);
