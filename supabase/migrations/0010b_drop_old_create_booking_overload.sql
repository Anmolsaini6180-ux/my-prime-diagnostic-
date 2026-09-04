-- ============================================================
-- Migration: 0010b_drop_old_create_booking_overload
-- ============================================================
-- Caught via get_advisors immediately after 0010: adding p_source as
-- a new trailing parameter made Postgres treat it as an OVERLOAD, not
-- a replacement (CREATE OR REPLACE only replaces a function with the
-- IDENTICAL parameter list). The OLD 15-argument create_booking --
-- with no auth.uid() check at all, and still GRANTed to anon from
-- migration 0005 -- was still fully live and exploitable alongside
-- the new one. This drops it outright, leaving exactly one
-- create_booking in existence.
-- ============================================================

drop function if exists public.create_booking(
  text, uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, text, uuid
);
