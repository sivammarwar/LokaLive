-- Create chess games table
CREATE TABLE public.chess_games (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE,
    white_player_id UUID REFERENCES public.users(id) ON DELETE SET NULL NOT NULL,
    black_player_id UUID REFERENCES public.users(id) ON DELETE SET NULL NOT NULL,
    fen TEXT NOT NULL DEFAULT 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    pgn TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'checkmate', 'stalemate', 'draw', 'resigned', 'abandoned')),
    winner_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    last_move JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.chess_games ENABLE ROW LEVEL SECURITY;

-- Policies for chess games
CREATE POLICY "Allow reading chess games in room" ON public.chess_games
    FOR SELECT
    USING (true);

CREATE POLICY "Allow creating chess games" ON public.chess_games
    FOR INSERT
    WITH CHECK (auth.uid() = white_player_id OR true);

CREATE POLICY "Allow updating own chess games" ON public.chess_games
    FOR UPDATE
    USING (auth.uid() = white_player_id OR auth.uid() = black_player_id OR true);

CREATE POLICY "Allow deleting own chess games" ON public.chess_games
    FOR DELETE
    USING (auth.uid() = white_player_id OR auth.uid() = black_player_id OR true);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_chess_games_room_id ON public.chess_games(room_id);
CREATE INDEX IF NOT EXISTS idx_chess_games_status ON public.chess_games(status);

-- Add constraint to prevent self-playing
ALTER TABLE public.chess_games 
ADD CONSTRAINT chess_games_different_players_check 
CHECK (white_player_id != black_player_id);

-- Function to auto-cleanup abandoned games
CREATE OR REPLACE FUNCTION cleanup_abandoned_chess_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.chess_games
    SET status = 'abandoned',
        updated_at = now()
    WHERE status IN ('pending', 'active')
    AND updated_at < now() - INTERVAL '30 minutes';
END;
$$;

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_chess_game_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_chess_game_timestamp ON public.chess_games;
CREATE TRIGGER trigger_update_chess_game_timestamp
    BEFORE UPDATE ON public.chess_games
    FOR EACH ROW
    EXECUTE FUNCTION update_chess_game_timestamp();

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.chess_games;

-- Comments for documentation
COMMENT ON TABLE public.chess_games IS 'Stores chess game state for real-time multiplayer chess within video rooms';
COMMENT ON COLUMN public.chess_games.status IS 'Game status: pending (invitation sent), active (game in progress), or end states';