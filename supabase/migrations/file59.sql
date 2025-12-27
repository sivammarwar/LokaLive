ALTER TABLE chess_games 
ADD COLUMN IF NOT EXISTS chess_room_id UUID REFERENCES rooms(id) ON DELETE SET NULL;

-- Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_chess_games_chess_room_id 
ON chess_games(chess_room_id);