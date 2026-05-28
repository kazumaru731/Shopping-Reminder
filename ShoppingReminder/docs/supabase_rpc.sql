-- =================================================================
-- Shopping Reminder: アカウント自己削除（退会）用 PostgreSQL 関数 (RPC)
-- 
-- 【目的】
-- Supabase のクライアントSDKからはセキュリティ上の制約により、一般ユーザー権限で
-- 自分自身の auth.users レコードを直接削除することができません。
-- この問題を解決するため、セキュアな特権権限（SECURITY DEFINER）で実行される
-- ストアドファンクションを定義し、アプリから RPC として安全に呼び出せるようにします。
--
-- 【実行方法】
-- Supabase ダッシュボード の 「SQL Editor」 にこのスクリプト全体を貼り付け、
-- 「Run」をクリックして実行してください。
-- =================================================================

-- 既存の同名関数があれば一旦削除して再定義します
drop function if exists public.delete_own_account();

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer -- 重要: 特権ユーザーの権限で実行することで auth.users への DELETE 操作を許可します
set search_path = public, auth -- 検索パスを固定し、検索パスのハイジャック攻撃を防ぐセキュア設計
as $$
declare
  target_user_id uuid;
begin
  -- 呼び出し元の認証済みユーザーIDを取得
  target_user_id := auth.uid();
  
  -- 認証チェック（念のため）
  if target_user_id is null then
    raise exception '認証されていないリクエストです。アカウント削除を実行できません。';
  end if;

  -- -------------------------------------------------------------
  -- 【データの整合性維持】
  -- 外部キーに ON DELETE CASCADE が設定されていない関連テーブルを
  -- 安全に掃除（クリーンアップ）するために、個別削除を明示的に実行します。
  -- -------------------------------------------------------------

  -- 1. プッシュ通知トークン情報の削除
  delete from public.push_tokens 
  where user_id = target_user_id;

  -- 2. グループメンバーシップ（中間テーブル）の削除
  delete from public.group_members 
  where user_id = target_user_id;

  -- 3. アプリケーション用プロフィールテーブルの削除
  delete from public.profiles 
  where id = target_user_id;

  -- 4. 最後に認証マスタ（auth.users）からアカウント自体を完全に削除
  -- これにより、Supabase 認証機能からもユーザーデータが安全かつ完全に消去されます。
  delete from auth.users 
  where id = target_user_id;

end;
$$;

-- -------------------------------------------------------------
-- 【権限設定】
-- 悪意ある未ログインユーザーや無関係な権限による実行を遮断するため、
-- 認証済みユーザー（authenticated）のみに関数の実行権限を付与します。
-- -------------------------------------------------------------
revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
