-- Run in Supabase SQL Editor
-- This creates a backup of your current state
CREATE TABLE room_participants_backup AS SELECT * FROM room_participants;
CREATE TABLE rooms_backup AS SELECT * FROM rooms;