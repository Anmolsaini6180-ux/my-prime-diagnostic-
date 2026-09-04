-- ============================================================
-- Migration: 0010e_activity_log_actor_fk_set_null
-- ============================================================
-- Found while cleaning up this session's test accounts: activity_log
-- .actor_id defaulted to ON DELETE NO ACTION (implicit default),
-- which means deleting ANY auth.users row that ever performed a
-- logged action becomes permanently impossible -- clearly wrong for
-- an audit log (staff leave; accounts get removed). actor_name/
-- actor_role are already denormalized as plain text at write time
-- specifically so the log entry stays meaningful even if actor_id
-- later goes null -- this migration makes that the actual behavior.
-- ============================================================

alter table public.activity_log
  drop constraint activity_log_actor_id_fkey,
  add constraint activity_log_actor_id_fkey
    foreign key (actor_id) references auth.users(id) on delete set null;
