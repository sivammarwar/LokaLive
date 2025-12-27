// src/lib/signalingUtils.ts - FIXED Signaling with Correct Supabase Filters

import { supabase } from '@/integrations/supabase/client';

interface Signal {
  room_id: string;
  sender_id: string;
  target_id?: string | null;
  message_type: 'offer' | 'answer' | 'ice-candidate' | 'join' | 'leave';
  payload: any;
}

// Queue for batching signals
let signalQueue: Signal[] = [];
let batchTimeout: NodeJS.Timeout | null = null;
let isSending = false;

/**
 * Send multiple signals in a single batch
 */
const sendSignalBatch = async (signals: Signal[]) => {
  if (signals.length === 0 || isSending) return;
  
  isSending = true;
  
  try {
    const { error } = await supabase.from('signaling').insert(signals);
    
    if (error) {
      console.error('❌ Batch send failed:', error);
    } else {
      console.log(`📦 Sent ${signals.length} signals in batch`);
    }
  } catch (error) {
    console.error('❌ Batch send error:', error);
  } finally {
    isSending = false;
  }
};

/**
 * Queue a signal with priority-based batching
 */
export const queueSignal = (signal: Signal) => {
  signalQueue.push(signal);
  
  // Priority: ice-candidate > offer/answer > join/leave
  signalQueue.sort((a, b) => {
    const priority: Record<string, number> = { 
      'ice-candidate': 1, 
      'offer': 2, 
      'answer': 2, 
      'join': 3, 
      'leave': 3 
    };
    return priority[a.message_type] - priority[b.message_type];
  });
  
  // Limit queue size
  if (signalQueue.length > 100) {
    console.warn('⚠️ Signal queue overflow, keeping only recent 50');
    signalQueue = signalQueue.slice(-50);
  }
  
  if (batchTimeout) clearTimeout(batchTimeout);
  
  const roomSize = signalQueue.filter(s => s.room_id === signal.room_id).length;
  const batchSize = Math.min(5, Math.max(1, Math.floor(roomSize / 2)));
  const batchDelay = Math.max(10, 100 - (roomSize * 5));
  
  // Send ICE candidates more aggressively
  if (signal.message_type === 'ice-candidate' && signalQueue.length >= 3) {
    sendSignalBatch([...signalQueue]);
    signalQueue = [];
    return;
  }
  
  if (signalQueue.length >= batchSize) {
    sendSignalBatch([...signalQueue]);
    signalQueue = [];
  } else {
    batchTimeout = setTimeout(() => {
      if (signalQueue.length > 0) {
        sendSignalBatch([...signalQueue]);
        signalQueue = [];
      }
    }, batchDelay);
  }
};

/**
 * 🔥 FIXED: Subscribe to signaling messages
 * Supabase realtime only supports SINGLE column filters!
 * We filter client-side for multi-column conditions.
 */
export const subscribeToSignaling = (
  roomId: string,
  userId: string,
  onSignal: (signal: any) => void
) => {
  console.log(`🔌 Subscribing to signaling for room: ${roomId}, user: ${userId}`);
  
  const channel = supabase
    .channel(`signaling-${roomId}`)
    // 🔥 FIX: Only filter by room_id (single column filter)
    // Then filter by target_id client-side
    .on('postgres_changes', {
      event: 'INSERT',
      schema: 'public',
      table: 'signaling',
      filter: `room_id=eq.${roomId}`
    }, (payload) => {
      const signal = payload.new as Signal;
      
      // 🔥 CLIENT-SIDE FILTERING
      // Skip our own messages
      if (signal.sender_id === userId) {
        console.log(`⏭️ Skipping own signal: ${signal.message_type}`);
        return;
      }
      
      // Process if: targeted at us OR broadcast (no target)
      if (signal.target_id === userId || signal.target_id === null) {
        const targetType = signal.target_id ? 'targeted' : 'broadcast';
        console.log(`📨 Received ${targetType} signal: ${signal.message_type} from ${signal.sender_id}`);
        onSignal(signal);
      } else {
        console.log(`⏭️ Skipping signal for another user: ${signal.target_id}`);
      }
    })
    .subscribe((status) => {
      console.log(`📡 Signaling channel status: ${status}`);
      
      if (status === 'SUBSCRIBED') {
        console.log('✅ Successfully subscribed to signaling channel');
      } else if (status === 'CHANNEL_ERROR') {
        console.error('❌ Signaling channel error - check RLS policies!');
      } else if (status === 'TIMED_OUT') {
        console.warn('⏰ Signaling channel subscription timed out');
      }
    });

  return channel;
};

/**
 * Subscribe to room participants
 */
export const subscribeToRoomParticipants = (
  roomId: string,
  onParticipantChange: (participants: any[]) => void
) => {
  console.log(`👥 Subscribing to participants for room: ${roomId}`);
  
  // Fetch initial participants immediately
  const fetchParticipants = async () => {
    const { data, error } = await supabase
      .from('room_participants')
      .select(`
        id,
        user_id,
        users!inner(display_name, membership_tier, diamonds, gender)
      `)
      .eq('room_id', roomId)
      .is('left_at', null);
    
    if (error) {
      console.error('❌ Error fetching participants:', error);
      return;
    }
    
    const participants = (data || []).map((p: any) => ({
      id: p.id,
      user_id: p.user_id,
      display_name: p.users.display_name,
      membership_tier: p.users.membership_tier || 'free',
      diamonds: p.users.diamonds || 0,
      gender: p.users.gender,
    }));
    
    console.log(`✅ Fetched ${participants.length} active participants`);
    onParticipantChange(participants);
  };
  
  // Fetch immediately
  fetchParticipants();
  
  const channel = supabase
    .channel(`room-participants-${roomId}`)
    .on('postgres_changes', {
      event: '*',
      schema: 'public',
      table: 'room_participants',
      filter: `room_id=eq.${roomId}`
    }, () => {
      console.log('👥 Participant change detected, refetching...');
      fetchParticipants();
    })
    .subscribe((status) => {
      console.log(`📡 Participants channel status: ${status}`);
    });

  return channel;
};

/**
 * Subscribe to chess game events
 */
export const subscribeToChessGames = (
  roomId: string,
  onGameEvent: (event: 'INSERT' | 'UPDATE', game: any) => void
) => {
  console.log(`♟️ Subscribing to chess games for room: ${roomId}`);
  
  const channel = supabase
    .channel(`chess-games-${roomId}`)
    .on('postgres_changes', {
      event: 'INSERT',
      schema: 'public',
      table: 'chess_games',
      filter: `room_id=eq.${roomId}`
    }, (payload) => {
      console.log('♟️ New chess game:', payload.new.id);
      onGameEvent('INSERT', payload.new);
    })
    .on('postgres_changes', {
      event: 'UPDATE',
      schema: 'public',
      table: 'chess_games',
      filter: `room_id=eq.${roomId}`
    }, (payload) => {
      console.log('♟️ Chess game updated:', payload.new.status);
      onGameEvent('UPDATE', payload.new);
    })
    .subscribe((status) => {
      console.log(`📡 Chess games channel status: ${status}`);
    });

  return channel;
};

/**
 * Subscribe to room chat messages
 */
export const subscribeToRoomChat = (
  roomId: string,
  onMessage: (message: any) => void
) => {
  console.log(`💬 Subscribing to chat for room: ${roomId}`);
  
  const channel = supabase
    .channel(`room-chat-${roomId}`)
    .on('postgres_changes', {
      event: 'INSERT',
      schema: 'public',
      table: 'room_chat_messages',
      filter: `room_id=eq.${roomId}`
    }, (payload) => {
      console.log('💬 New chat message:', payload.new);
      onMessage(payload.new);
    })
    .subscribe((status) => {
      console.log(`📡 Chat channel status: ${status}`);
    });

  return channel;
};

/**
 * Clean up old signals
 */
export const cleanupOldSignals = async (roomId: string) => {
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  
  try {
    const { error } = await supabase
      .from('signaling')
      .delete()
      .eq('room_id', roomId)
      .lt('created_at', oneHourAgo);
    
    if (error) {
      console.error('❌ Error cleaning up old signals:', error);
    } else {
      console.log('🧹 Cleaned up old signals');
    }
  } catch (error) {
    console.error('❌ Cleanup error:', error);
  }
};

/**
 * Flush pending signals immediately
 */
export const flushSignalQueue = () => {
  if (signalQueue.length > 0) {
    console.log(`🚀 Flushing ${signalQueue.length} pending signals`);
    sendSignalBatch([...signalQueue]);
    signalQueue = [];
  }
  
  if (batchTimeout) {
    clearTimeout(batchTimeout);
    batchTimeout = null;
  }
};

/**
 * Get current queue size
 */
export const getQueueSize = () => signalQueue.length;

/**
 * Clear the signal queue
 */
export const clearQueue = () => {
  console.log('🧹 Clearing signal queue');
  signalQueue = [];
  if (batchTimeout) {
    clearTimeout(batchTimeout);
    batchTimeout = null;
  }
};

/**
 * Send a signal immediately (bypass queue)
 */
export const sendSignalImmediate = async (signal: Signal) => {
  console.log(`⚡ Sending immediate signal: ${signal.message_type}`);
  
  try {
    const { error } = await supabase.from('signaling').insert([signal]);
    
    if (error) {
      console.error('❌ Immediate send failed:', error);
      return false;
    }
    
    console.log('✅ Immediate signal sent');
    return true;
  } catch (error) {
    console.error('❌ Immediate send error:', error);
    return false;
  }
};

/**
 * Batch cleanup old signals
 */
export const batchCleanupSignals = async (roomId: string, olderThanMinutes: number = 5) => {
  const cutoffTime = new Date(Date.now() - olderThanMinutes * 60 * 1000).toISOString();
  
  try {
    const { data, error } = await supabase
      .from('signaling')
      .delete()
      .eq('room_id', roomId)
      .lt('created_at', cutoffTime)
      .select('count');
    
    if (error) {
      console.error('❌ Batch cleanup error:', error);
      return 0;
    }
    
    const count = data?.length || 0;
    if (count > 0) {
      console.log(`🧹 Cleaned up ${count} old signals`);
    }
    
    return count;
  } catch (error) {
    console.error('❌ Batch cleanup error:', error);
    return 0;
  }
};
