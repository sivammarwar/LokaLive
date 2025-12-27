-- Create signaling table for WebRTC messages
CREATE TABLE public.signaling (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    target_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    message_type TEXT NOT NULL CHECK (message_type IN ('offer', 'answer', 'ice-candidate', 'join', 'leave')),
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.signaling ENABLE ROW LEVEL SECURITY;

-- Policies for signaling
CREATE POLICY "Allow inserting signals" ON public.signaling 
    FOR INSERT 
    WITH CHECK (auth.uid() = sender_id OR true);

CREATE POLICY "Allow reading signals in room" ON public.signaling 
    FOR SELECT 
    USING (true);

CREATE POLICY "Allow deleting own signals" ON public.signaling 
    FOR DELETE 
    USING (auth.uid() = sender_id OR true);

-- Enable realtime for signaling
ALTER PUBLICATION supabase_realtime ADD TABLE public.signaling;

-- Add indexes for faster queries
CREATE INDEX idx_signaling_room_id ON public.signaling(room_id);
CREATE INDEX idx_signaling_target_id ON public.signaling(target_id);
CREATE INDEX idx_signaling_created_at ON public.signaling(created_at);

-- Auto-cleanup old signals (older than 1 hour)
CREATE OR REPLACE FUNCTION cleanup_old_signals()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.signaling WHERE created_at < now() - INTERVAL '1 hour';
END;
$$;