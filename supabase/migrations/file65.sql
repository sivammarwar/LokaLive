-- ============================================
-- 🔧 CREATE CHESS SIGNALING TABLE
-- Required for ChessGameView.tsx
-- ============================================

CREATE TABLE IF NOT EXISTS chess_signaling (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chess_game_id UUID NOT NULL REFERENCES chess_games(id) ON DELETE CASCADE,
  from_user UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user UUID NOT NULL REFERENCES users(id),
  signal_type TEXT NOT NULL,
  signal_data JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_chess_signaling_to_user ON chess_signaling(to_user);
CREATE INDEX IF NOT EXISTS idx_chess_signaling_chess_game ON chess_signaling(chess_game_id);
CREATE INDEX IF NOT EXISTS idx_chess_signaling_from_user ON chess_signaling(from_user);
CREATE INDEX IF NOT EXISTS idx_chess_signaling_created_at ON chess_signaling(created_at);

-- ============================================
-- 🔧 ADD ROW LEVEL SECURITY
-- ============================================
ALTER TABLE chess_signaling ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow users to manage chess signals" ON chess_signaling
FOR ALL USING (
  auth.uid() IN (from_user, to_user) OR
  EXISTS (
    SELECT 1 FROM chess_games cg
    WHERE cg.id = chess_signaling.chess_game_id
    AND (cg.white_player_id = auth.uid() OR cg.black_player_id = auth.uid())
  )
);

-- ============================================
-- 🔧 ADD TO REALTIME
-- ============================================
ALTER PUBLICATION supabase_realtime ADD TABLE chess_signaling;

-- ============================================
-- 🔧 VERIFICATION
-- ============================================
DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '✅ CHESS SIGNALING TABLE CREATED';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Table: chess_signaling';
  RAISE NOTICE 'Purpose: Separate signaling for chess WebRTC';
  RAISE NOTICE 'Used by: ChessGameView.tsx';
  RAISE NOTICE 'Distinct from: main signaling table (for video chat)';
  RAISE NOTICE '========================================';
END $$;