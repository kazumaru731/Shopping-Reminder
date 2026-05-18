-- グループテーブルにフラグ追加
ALTER TABLE groups ADD COLUMN allow_member_edit BOOLEAN DEFAULT FALSE;

-- リストテーブルにフラグ追加
ALTER TABLE lists ADD COLUMN allow_member_edit BOOLEAN DEFAULT FALSE;

-- アイテムテーブルにフラグ追加
ALTER TABLE items ADD COLUMN allow_collaborator_edit BOOLEAN DEFAULT FALSE;
