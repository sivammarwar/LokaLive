// ============================================
// CreateRoom.tsx - SIMPLIFIED GENDER-ONLY VERSION
// ============================================

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Logo } from '@/components/Logo';
import { HealthTokens } from '@/components/HealthTokens';
import { useUserStore } from '@/lib/userStore';
import { useDiamondStore } from '@/lib/diamondStore';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

import {
  Globe,
  Lock,
  Users,
  User,
  Copy,
  ArrowRight,
  LogOut,
  Crown,
  Sparkles,
  Gem,
  Wallet,
  Dices,
  Loader2,
  UserCheck,
  Eye,
  Zap,
} from 'lucide-react';
import { cn } from '@/lib/utils';

type RoomType = 'public' | 'private';
type RoomSize = 2 | 4;
type Gender = 'male' | 'female';
type MembershipTier = 'free' | 'premium' | 'premium_plus';

const genderOptions: { value: Gender; label: string; icon: React.ElementType }[] = [
  { value: 'male', label: 'Male', icon: User },
  { value: 'female', label: 'Female', icon: User },
];

const getMembershipStyle = (tier: MembershipTier) => {
  switch (tier) {
    case 'premium':
      return {
        textColor: 'text-blue-500',
        bgColor: 'bg-blue-500/10',
        borderColor: 'border-blue-500',
        icon: Crown,
        iconColor: 'text-blue-500',
        nameTagText: 'text-blue-500',
        label: 'Premium',
      };
    case 'premium_plus':
      return {
        textColor: 'text-yellow-500',
        bgColor: 'bg-yellow-500/10',
        borderColor: 'border-yellow-500',
        icon: Sparkles,
        iconColor: 'text-yellow-500',
        nameTagText: 'text-yellow-500',
        label: 'Premium+',
      };
    default:
      return {
        textColor: 'text-foreground',
        bgColor: 'bg-muted',
        borderColor: 'border-border',
        icon: null,
        iconColor: 'text-foreground',
        nameTagText: 'text-foreground',
        label: 'Free',
      };
  }
};

export default function CreateRoom() {
  const navigate = useNavigate();
  const { id: userId, displayName, healthTokens, clearUser } = useUserStore();
  const { diamonds } = useDiamondStore();
  
  const [roomType, setRoomType] = useState<RoomType>('public');
  const [roomSize, setRoomSize] = useState<RoomSize>(2);
  const [userGender, setUserGender] = useState<Gender>('male');
  const [privateRoomCode, setPrivateRoomCode] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [generatedRoom, setGeneratedRoom] = useState<{ code: string; id: string } | null>(null);
  const [membershipTier, setMembershipTier] = useState<MembershipTier>('free');
  
  // Active users state
  const [maleCount, setMaleCount] = useState<number | null>(null);
  const [femaleCount, setFemaleCount] = useState<number | null>(null);
  const [loadingCounts, setLoadingCounts] = useState(false);

  // Ludo voting state
  const [ludoVoteCount, setLudoVoteCount] = useState(0);
  const [hasVoted, setHasVoted] = useState(false);
  const [isVoting, setIsVoting] = useState(false);

  if (!userId) {
    navigate('/');
    return null;
  }

  // Fetch membership status
  useEffect(() => {
    const fetchMembershipStatus = async () => {
      if (!userId) return;

      const { data, error } = await supabase
        .from('users')
        .select('membership_tier, membership_expires_at')
        .eq('id', userId)
        .single();

      if (error) {
        console.error('Error fetching membership:', error);
        return;
      }

      if (data) {
        setMembershipTier(data.membership_tier as MembershipTier);
      }
    };

    fetchMembershipStatus();
  }, [userId]);

  // Fetch active user counts (for premium users)
  useEffect(() => {
    const fetchActiveCounts = async () => {
      if (membershipTier === 'free') {
        setMaleCount(null);
        setFemaleCount(null);
        return;
      }

      setLoadingCounts(true);
      try {
        const { data, error } = await supabase
          .rpc('get_active_users_by_gender');

        if (!error && data && data.length > 0) {
          setMaleCount(Number(data[0].male_count) || 0);
          setFemaleCount(Number(data[0].female_count) || 0);
        }
      } catch (error) {
        console.error('Error fetching active counts:', error);
      } finally {
        setLoadingCounts(false);
      }
    };

    fetchActiveCounts();

    // Refresh counts every 10 seconds for premium users
    if (membershipTier !== 'free') {
      const interval = setInterval(fetchActiveCounts, 10000);
      return () => clearInterval(interval);
    }
  }, [membershipTier]);
  // ============================================
// FIXED: Online Users Count Logic
// Replace lines 112-127 in your CreateRoom.tsx
// ============================================

// Fetch active user counts (for premium users)
useEffect(() => {
  const fetchActiveCounts = async () => {
    if (membershipTier === 'free') {
      setMaleCount(null);
      setFemaleCount(null);
      return;
    }

    setLoadingCounts(true);
    try {
      console.log('🔍 Fetching active user counts...');
      
      const { data, error } = await supabase
        .rpc('get_active_users_by_gender');

      console.log('📊 RPC Response:', { data, error });

      if (error) {
        console.error('❌ RPC Error:', error);
        throw error;
      }

      // ✅ FIX: Handle the response correctly
      if (data && data.length > 0) {
        const counts = data[0];
        console.log('✅ Parsed counts:', counts);
        
        setMaleCount(Number(counts.male_count) || 0);
        setFemaleCount(Number(counts.female_count) || 0);
        
        console.log(`👥 Males: ${counts.male_count}, Females: ${counts.female_count}`);
      } else if (data && typeof data === 'object' && 'male_count' in data) {
        // Handle case where data is a single object (not array)
        console.log('✅ Single object response:', data);
        setMaleCount(Number(data.male_count) || 0);
        setFemaleCount(Number(data.female_count) || 0);
      } else {
        console.log('⚠️ No data returned, setting to 0');
        setMaleCount(0);
        setFemaleCount(0);
      }
    } catch (error) {
      console.error('❌ Error fetching active counts:', error);
      // Set to 0 instead of null on error
      setMaleCount(0);
      setFemaleCount(0);
    } finally {
      setLoadingCounts(false);
    }
  };

  fetchActiveCounts();

  // Refresh counts every 10 seconds for premium users
  if (membershipTier !== 'free') {
    const interval = setInterval(fetchActiveCounts, 10000);
    return () => clearInterval(interval);
  }
}, [membershipTier]);

// ============================================
// OPTIONAL: Add real-time subscription for instant updates
// Add this useEffect after the one above
// ============================================

useEffect(() => {
  if (membershipTier === 'free') return;

  console.log('🔄 Setting up real-time subscription for online counts...');

  // Subscribe to room_participants changes
  const channel = supabase
    .channel('online-users-realtime')
    .on(
      'postgres_changes',
      {
        event: '*', // Listen to INSERT, UPDATE, DELETE
        schema: 'public',
        table: 'room_participants',
      },
      (payload) => {
        console.log('📡 Room participants changed:', payload);
        
        // Refetch counts when participants change
        supabase.rpc('get_active_users_by_gender').then(({ data, error }) => {
          if (!error && data && data.length > 0) {
            const counts = data[0];
            setMaleCount(Number(counts.male_count) || 0);
            setFemaleCount(Number(counts.female_count) || 0);
            console.log('✅ Realtime update - Males:', counts.male_count, 'Females:', counts.female_count);
          }
        });
      }
    )
    .subscribe((status) => {
      console.log('📡 Subscription status:', status);
    });

  return () => {
    console.log('🔌 Cleaning up real-time subscription');
    supabase.removeChannel(channel);
  };
}, [membershipTier]);

// ============================================
// ALTERNATIVE: Use the fast function for better performance
// Replace the RPC call with this:
// ============================================

// const { data, error } = await supabase.rpc('get_active_users_by_gender_fast');

// ============================================
// DEBUG: Add this button temporarily to test the function
// Add this inside your component's return statement
// ============================================

{/* DEBUG BUTTON - Remove after testing */}
{membershipTier !== 'free' && (
  <button
    onClick={async () => {
      console.log('🧪 Testing online users function...');
      
      // Test main function
      const result1 = await supabase.rpc('get_active_users_by_gender');
      console.log('📊 Main function result:', result1);
      
      // Test fast function
      const result2 = await supabase.rpc('get_active_users_by_gender_fast');
      console.log('⚡ Fast function result:', result2);
      
      // Test debug function
      const result3 = await supabase.rpc('debug_active_users');
      console.log('🔍 Debug data:', result3);
      
      alert('Check console for results');
    }}
    className="fixed bottom-4 left-4 bg-red-500 text-white px-4 py-2 rounded-lg z-50"
  >
    Test Online Users
  </button>
)}
  // Fetch Ludo vote count
  useEffect(() => {
    const fetchLudoVoteData = async () => {
      if (!userId) return;

      const { data: voteCountData, error: countError } = await supabase
        .rpc('get_ludo_vote_count');

      if (!countError && voteCountData !== null) {
        setLudoVoteCount(voteCountData);
      }

      const { data: hasVotedData, error: votedError } = await supabase
        .rpc('has_user_voted_ludo', { p_user_id: userId });

      if (!votedError && hasVotedData !== null) {
        setHasVoted(hasVotedData);
      }
    };

    fetchLudoVoteData();

    

    const channel = supabase
      .channel('ludo_votes_changes')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'ludo_votes',
        },
        () => {
          supabase.rpc('get_ludo_vote_count').then(({ data }) => {
            if (data !== null) setLudoVoteCount(data);
          });
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId]);

  const handleLudoVote = async () => {
    if (!userId || hasVoted || isVoting) return;

    setIsVoting(true);

    try {
      const { error } = await supabase
        .from('ludo_votes')
        .insert({ user_id: userId });

      if (error) {
        if (error.code === '23505') {
          toast.error('You have already voted! 🎲');
          setHasVoted(true);
        } else {
          throw error;
        }
      } else {
        setHasVoted(true);
        toast.success('Vote counted! Thanks for your support! 🎲');
        
        const { data } = await supabase.rpc('get_ludo_vote_count');
        if (data !== null) setLudoVoteCount(data);
      }
    } catch (error) {
      console.error('Error voting for Ludo:', error);
      toast.error('Failed to vote. Please try again.');
    } finally {
      setIsVoting(false);
    }
  };

  // ============================================
  // MAIN ROOM CREATION HANDLER
  // ============================================
  const handleCreateRoom = async () => {
    if (!userId) {
      toast.error('User ID not found');
      return;
    }
    
    setIsLoading(true);
    console.log('🚀 Starting room creation:', {
      roomType,
      roomSize,
      userGender,
    });

    try {
      if (roomType === 'public') {
        // PUBLIC ROOM MATCHING
        console.log('========================================');
        console.log('🔍 PUBLIC MATCHMAKING REQUEST');
        console.log('========================================');
        console.log('User ID:', userId);
        console.log('My Gender:', userGender);
        console.log('Room Size:', roomSize);
        console.log('========================================');
        
        // Leave existing rooms
        console.log('🚪 Leaving existing rooms...');
        const { data: leftCount } = await supabase
          .rpc('leave_all_user_rooms', { p_user_id: userId });
        
        if (leftCount && leftCount > 0) {
          console.log(`✅ Left ${leftCount} room(s)`);
          await new Promise(resolve => setTimeout(resolve, 500));
        }
        
        toast.info('Searching for compatible matches...');
        
        // Find or create room (simplified function)
        console.log('🔍 Calling find_compatible_room_simple...');
        
        const { data: roomData, error: findError } = await supabase.rpc(
          'find_compatible_room_simple',
          {
            p_user_id: userId,
            p_user_gender: userGender,
            p_room_size: roomSize,
          }
        );

        if (findError) {
          console.error('========================================');
          console.error('❌ MATCHMAKING ERROR');
          console.error('========================================');
          console.error('Error:', findError);
          toast.error(`Matchmaking failed: ${findError.message}`);
          setIsLoading(false);
          return;
        }

        if (!roomData || roomData.length === 0) {
          console.error('❌ No room returned from matchmaking');
          toast.error('Failed to create or find room');
          setIsLoading(false);
          return;
        }

        const result = roomData[0];
        const newRoomId = result.matched_room_id;
        const isNewRoom = result.is_new_room;

        console.log('========================================');
        console.log('✅ MATCHMAKING RESULT');
        console.log('========================================');
        console.log('Room ID:', newRoomId);
        console.log('Is New Room:', isNewRoom);
        console.log('========================================');

        if (!newRoomId) {
          console.error('❌ No room ID in result:', result);
          toast.error('Invalid matchmaking result');
          setIsLoading(false);
          return;
        }

        // Join the room
        console.log('🚪 Joining room...');
        const { data: joinData, error: joinError } = await supabase.rpc(
          'join_room_if_available',
          {
            p_room_id: newRoomId,
            p_user_id: userId,
          }
        );

        if (joinError) {
          console.error('❌ Join error:', joinError);
          toast.error(`Failed to join: ${joinError.message}`);
          setIsLoading(false);
          return;
        }

        const joinResult = joinData as {
          success: boolean;
          error?: string;
          message?: string;
        };

        console.log('📊 Join result:', joinResult);

        if (!joinResult.success) {
          if (joinResult.error === 'room_full') {
            console.log('⚠️ Room full, retrying...');
            setTimeout(() => {
              setIsLoading(false);
              handleCreateRoom();
            }, 1000);
            return;
          }
          console.error('❌ Join failed:', joinResult.message);
          toast.error(joinResult.message || 'Failed to join room');
          setIsLoading(false);
          return;
        }

        console.log('✅ Successfully joined room');
        
        toast.success(
          isNewRoom 
            ? 'Room created! Waiting for match...' 
            : 'Match found! Connecting...'
        );
        
        await new Promise(resolve => setTimeout(resolve, 800));
        
        console.log('🎯 Navigating to room:', newRoomId);
        console.log('========================================');
        
        navigate(`/room/${newRoomId}`, { replace: true });
      } else {
        // PRIVATE ROOM CREATION
        console.log('🔒 Creating private room...');
        
        const { data: leftCount } = await supabase
          .rpc('leave_all_user_rooms', { p_user_id: userId });
        
        if (leftCount && leftCount > 0) {
          console.log(`✅ Left ${leftCount} room(s)`);
          await new Promise(resolve => setTimeout(resolve, 300));
        }
        
        const { data: room, error } = await supabase
          .from('rooms')
          .insert({
            room_type: 'private',
            room_size: roomSize,
            creator_id: userId,
            is_active: true,
          })
          .select()
          .single();

        if (error) {
          console.error('❌ Private room creation error:', error);
          throw error;
        }

        console.log('✅ Private room created:', room.id);

        const { error: joinError } = await supabase
          .from('room_participants')
          .insert({
            room_id: room.id,
            user_id: userId,
          });

        if (joinError && joinError.code !== '23505') {
          console.error('❌ Join error:', joinError);
          throw joinError;
        }

        if (room.room_code) {
          setGeneratedRoom({ code: room.room_code, id: room.id });
          toast.success('Private room created!');
        } else {
          toast.error('Room code not generated');
        }
      }
    } catch (error: any) {
      console.error('❌ Unhandled error:', error);
      toast.error(error?.message || 'Failed to create room. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  // ============================================
  // JOIN PRIVATE ROOM HANDLER
  // ============================================
  const handleJoinPrivateRoom = async () => {
    const trimmedCode = privateRoomCode.toUpperCase().trim();
    
    if (!trimmedCode) {
      toast.error('Please enter a room code');
      return;
    }

    if (trimmedCode.length !== 6) {
      toast.error('Room code must be 6 characters');
      return;
    }

    setIsLoading(true);
    console.log('🔑 Joining private room:', trimmedCode);

    try {
      console.log('🚪 Leaving existing rooms...');
      const { data: leftCount } = await supabase
        .rpc('leave_all_user_rooms', { p_user_id: userId });
      
      if (leftCount && leftCount > 0) {
        console.log(`✅ Left ${leftCount} room(s)`);
        await new Promise(resolve => setTimeout(resolve, 800));
      }

      const { data: room, error: roomError } = await supabase
        .from('rooms')
        .select('*')
        .eq('room_code', trimmedCode)
        .eq('is_active', true)
        .eq('room_type', 'private')
        .maybeSingle();

      if (roomError) {
        console.error('❌ Room query error:', roomError);
        throw roomError;
      }

      if (!room) {
        toast.error('Room not found or no longer active');
        return;
      }

      console.log('✅ Found room:', room.id);

      const { data: joinData, error: joinError } = await supabase.rpc(
        'join_room_if_available',
        {
          p_room_id: room.id,
          p_user_id: userId,
        }
      );

      if (joinError) {
        console.error('❌ Join error:', joinError);
        throw joinError;
      }

      const joinResult = typeof joinData === 'string' 
        ? JSON.parse(joinData) 
        : joinData;

      console.log('📊 Join result:', joinResult);

      if (!joinResult.success && !joinResult.already_joined) {
        if (joinResult.error === 'room_full') {
          toast.error('Room is full');
          return;
        }
        throw new Error(joinResult.message || 'Failed to join room');
      }

      console.log('✅ Successfully joined room');
      toast.success('Joined the room!');
      
      await new Promise(resolve => setTimeout(resolve, 800));
      navigate(`/room/${room.id}`);
      
    } catch (error: any) {
      console.error('❌ Join room error:', error);
      toast.error(error.message || 'Failed to join room. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const copyRoomCode = () => {
    if (generatedRoom) {
      navigator.clipboard.writeText(generatedRoom.code);
      toast.success('Room code copied!');
    }
  };

  const handleLogout = () => {
    clearUser();
    navigate('/');
  };

  const membershipStyle = getMembershipStyle(membershipTier);
  const MembershipIcon = membershipStyle.icon;

  const formatVoteCount = (count: number) => {
    return count.toLocaleString('en-IN');
  };

  const isPremium = membershipTier === 'premium' || membershipTier === 'premium_plus';

  return (
    <div className="min-h-screen flex flex-col p-4 relative overflow-hidden">
      {/* Background */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-0 left-1/4 w-96 h-96 bg-primary/10 rounded-full blur-[150px]" />
        <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-accent/10 rounded-full blur-[150px]" />
      </div>

      {/* Header */}
      <header className="flex items-center justify-between mb-8 relative z-10">
        <Logo size="sm" />
        <div className="flex items-center gap-3 flex-wrap">
          {/* Ludo Vote Button */}
          <div className="relative group">
            <Button
              variant={hasVoted ? "outline" : "default"}
              size="sm"
              onClick={handleLudoVote}
              disabled={hasVoted || isVoting}
              className={cn(
                "gap-2 transition-all duration-300",
                hasVoted 
                  ? "border-green-500/50 text-green-500 hover:bg-green-500/10" 
                  : "bg-gradient-to-r from-orange-500 to-red-500 hover:from-orange-600 hover:to-red-600 border-0 shadow-lg hover:shadow-xl"
              )}
            >
              <Dices className={cn("h-4 w-4", isVoting && "animate-spin")} />
              <span className="font-semibold">
                {hasVoted ? `✓ ${formatVoteCount(ludoVoteCount)}` : formatVoteCount(ludoVoteCount)}
              </span>
            </Button>
            
            <div className="absolute top-full left-1/2 -translate-x-1/2 mt-2 px-4 py-2 bg-black/90 text-white text-sm rounded-lg whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity duration-200 pointer-events-none z-50">
              {hasVoted 
                ? "1 million likes cross hote hi…Ludo aa jaayega bhai, pakka 😂🎲" 
                : "1 million likes cross hote hi…Ludo aa jaayega bhai, pakka 😂🎲"
              }
              <div className="absolute -top-1 left-1/2 -translate-x-1/2 w-2 h-2 bg-black/90 rotate-45" />
            </div>
          </div>

          {/* Diamond Balance */}
          <div className="glass rounded-full px-4 py-2 flex items-center gap-2 border border-blue-500/30">
            <Gem className="h-4 w-4 text-blue-400" />
            <span className="text-sm font-semibold text-blue-400">{diamonds}</span>
          </div>

          {/* Buy Diamonds */}
          <Button
            variant="outline"
            size="sm"
            onClick={() => navigate('/buy-diamonds')}
            className="gap-2 border-blue-500/50 text-blue-500 hover:bg-blue-500/10"
          >
            <Gem className="h-4 w-4" />
            Buy
          </Button>

          {/* Withdraw */}
          <Button
            variant="outline"
            size="sm"
            onClick={() => navigate('/withdraw-diamonds')}
            className="gap-2 border-green-500/50 text-green-500 hover:bg-green-500/10"
          >
            <Wallet className="h-4 w-4" />
            Withdraw
          </Button>

          {/* Upgrade Button */}
          {membershipTier === 'free' && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => navigate('/premium')}
              className="gap-2 border-yellow-500/50 text-yellow-500 hover:bg-yellow-500/10"
            >
              <Sparkles className="h-4 w-4" />
              Upgrade
            </Button>
          )}

          {/* User Info Badge */}
          <div className={cn(
            "flex items-center gap-3 glass rounded-full px-4 py-2",
            membershipStyle.bgColor,
            membershipStyle.borderColor,
            "border"
          )}>
            {MembershipIcon && (
              <MembershipIcon className={cn("h-4 w-4", membershipStyle.textColor)} />
            )}
            <span className={cn("text-sm font-medium", membershipStyle.textColor)}>
              {displayName}
            </span>
            <HealthTokens 
              tokens={healthTokens} 
              size="sm" 
              membershipTier={membershipTier}
            />
          </div>

          {/* Logout */}
          <Button variant="ghost" size="icon" onClick={handleLogout}>
            <LogOut className="h-5 w-5" />
          </Button>
        </div>
      </header>

      {/* Main Content */}
      <main className="flex-1 flex items-center justify-center relative z-10">
        <div className="w-full max-w-2xl space-y-8 animate-slide-up">
          <div className="text-center space-y-2">
            <h1 className="text-3xl font-bold">Create or Join a Room</h1>
            <p className="text-muted-foreground">Choose your gender and start matching</p>
          </div>

          {generatedRoom ? (
            <div className="glass-strong rounded-2xl p-8 space-y-6 text-center">
              <div className="space-y-2">
                <p className="text-muted-foreground">Share this code with your friends:</p>
                <div className="flex items-center justify-center gap-3">
                  <span className="text-4xl font-bold tracking-widest text-gradient-primary">
                    {generatedRoom.code}
                  </span>
                  <Button variant="outline" size="icon" onClick={copyRoomCode}>
                    <Copy className="h-5 w-5" />
                  </Button>
                </div>
              </div>
              <div className="flex gap-4 justify-center">
                <Button variant="outline" onClick={() => setGeneratedRoom(null)}>
                  Create Another
                </Button>
                <Button
                  variant="hero"
                  onClick={() => navigate(`/room/${generatedRoom.id}`)}
                >
                  Enter Room
                  <ArrowRight className="h-5 w-5" />
                </Button>
              </div>
            </div>
          ) : (
            <div className="glass-strong rounded-2xl p-8 space-y-8">
              {/* Room Type Selection */}
              <div className="space-y-3">
                <label className="text-sm font-medium">Room Type</label>
                <div className="grid grid-cols-2 gap-4">
                  <button
                    onClick={() => setRoomType('public')}
                    className={cn(
                      'flex items-center justify-center gap-3 p-4 rounded-xl border-2 transition-all duration-300',
                      roomType === 'public'
                        ? 'border-primary bg-primary/10 text-primary'
                        : 'border-border hover:border-primary/50'
                    )}
                  >
                    <Globe className="h-5 w-5" />
                    <span className="font-semibold">Public</span>
                  </button>
                  <button
                    onClick={() => setRoomType('private')}
                    className={cn(
                      'flex items-center justify-center gap-3 p-4 rounded-xl border-2 transition-all duration-300',
                      roomType === 'private'
                        ? 'border-primary bg-primary/10 text-primary'
                        : 'border-border hover:border-primary/50'
                    )}
                  >
                    <Lock className="h-5 w-5" />
                    <span className="font-semibold">Private</span>
                  </button>
                </div>
              </div>

              {/* Room Size */}
              <div className="space-y-3">
                <label className="text-sm font-medium">Room Size</label>
                <div className="grid grid-cols-2 gap-4">
                  {[2, 4].map((size) => (
                    <button
                      key={size}
                      onClick={() => setRoomSize(size as RoomSize)}
                      className={cn(
                        'flex items-center justify-center gap-3 p-4 rounded-xl border-2 transition-all duration-300',
                        roomSize === size
                          ? 'border-primary bg-primary/10 text-primary'
                          : 'border-border hover:border-primary/50'
                      )}
                    >
                      <Users className="h-5 w-5" />
                      <span className="font-semibold">{size} People</span>
                    </button>
                  ))}
                </div>
              </div>

              {/* Public Room Options */}
              {roomType === 'public' && (
                <>
                  {/* Your Gender */}
                  <div className="space-y-3">
                    <label className="text-sm font-medium">Your Gender</label>
                    <div className="grid grid-cols-2 gap-4">
                      {genderOptions.map((option) => (
                        <button
                          key={option.value}
                          onClick={() => setUserGender(option.value)}
                          className={cn(
                            'flex flex-col items-center gap-2 p-4 rounded-xl border-2 transition-all duration-300',
                            userGender === option.value
                              ? 'border-primary bg-primary/10 text-primary'
                              : 'border-border hover:border-primary/50'
                          )}
                        >
                          <option.icon className="h-6 w-6" />
                          <span className="text-sm font-medium">{option.label}</span>
                        </button>
                      ))}
                    </div>
                  </div>

                  {/* Active Users Counter (Premium Feature) */}
                  <div className={cn(
                    "rounded-xl border-2 p-4 transition-all duration-300",
                    isPremium 
                      ? "border-primary/30 bg-gradient-to-br from-primary/5 to-accent/5" 
                      : "border-border/50 bg-muted/20"
                  )}>
                    <div className="flex items-center justify-between mb-3">
                      <div className="flex items-center gap-2">
                        <UserCheck className={cn(
                          "h-5 w-5",
                          isPremium ? "text-primary" : "text-muted-foreground"
                        )} />
                        <span className={cn(
                          "text-sm font-semibold",
                          isPremium ? "text-primary" : "text-muted-foreground"
                        )}>
                          Active Users Online
                        </span>
                      </div>
                      {isPremium && (
                        <Zap className="h-4 w-4 text-yellow-500 animate-pulse" />
                      )}
                    </div>

                    {isPremium ? (
                      <div className="space-y-2">
                        {loadingCounts ? (
                          <div className="flex items-center justify-center py-4">
                            <Loader2 className="h-5 w-5 animate-spin text-primary" />
                          </div>
                        ) : (
                          <div className="grid grid-cols-2 gap-3">
                            {/* Male Count */}
                            <div className="glass rounded-lg p-3 border border-blue-500/20">
                              <div className="flex items-center gap-2 mb-1">
                                <User className="h-4 w-4 text-blue-400" />
                                <span className="text-xs text-muted-foreground">Males</span>
                              </div>
                              <div className="text-2xl font-bold text-blue-400">
                                {maleCount ?? 0}
                              </div>
                              <div className="text-xs text-muted-foreground mt-1">
                                online now
                              </div>
                            </div>

                            {/* Female Count */}
                            <div className="glass rounded-lg p-3 border border-pink-500/20">
                              <div className="flex items-center gap-2 mb-1">
                                <User className="h-4 w-4 text-pink-400" />
                                <span className="text-xs text-muted-foreground">Females</span>
                              </div>
                              <div className="text-2xl font-bold text-pink-400">
                                {femaleCount ?? 0}
                              </div>
                              <div className="text-xs text-muted-foreground mt-1">
                                online now
                              </div>
                            </div>
                          </div>
                        )}
                      </div>
                    ) : (
                      <div className="text-center py-4">
                        <div className="flex items-center justify-center gap-2 mb-2">
                          <Eye className="h-5 w-5 text-muted-foreground" />
                          <Lock className="h-4 w-4 text-muted-foreground" />
                        </div>
                        <p className="text-xs text-muted-foreground mb-3">
                          See how many males and females are active right now
                        </p>
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => navigate('/premium')}
                          className="gap-2 border-primary/50 text-primary hover:bg-primary/10"
                        >
                          <Sparkles className="h-4 w-4" />
                          Unlock with Premium
                        </Button>
                      </div>
                    )}
                  </div>
                </>
              )}

              {/* Action Buttons */}
              <div className="space-y-4">
                <Button
                  variant="hero"
                  size="xl"
                  className="w-full"
                  onClick={handleCreateRoom}
                  disabled={isLoading}
                >
                  {isLoading ? (
                    <div className="flex items-center gap-2">
                      <Loader2 className="w-5 h-5 animate-spin" />
                      {roomType === 'public' ? 'Finding Match...' : 'Creating Room...'}
                    </div>
                  ) : (
                    <>
                      {roomType === 'public' ? 'Start Matching' : 'Create Private Room'}
                      <ArrowRight className="h-5 w-5" />
                    </>
                  )}
                </Button>

                {roomType === 'private' && (
                  <>
                    <div className="relative">
                      <div className="absolute inset-0 flex items-center">
                        <div className="w-full border-t border-border" />
                      </div>
                      <div className="relative flex justify-center text-xs uppercase">
                        <span className="bg-card px-2 text-muted-foreground">or join with code</span>
                      </div>
                    </div>
                    <div className="flex gap-3">
                      <Input
                        placeholder="Enter room code..."
                        value={privateRoomCode}
                        onChange={(e) => setPrivateRoomCode(e.target.value.toUpperCase())}
                        maxLength={6}
                        className="text-center tracking-widest text-lg font-semibold"
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && privateRoomCode.trim()) {
                            handleJoinPrivateRoom();
                          }
                        }}
                      />
                      <Button
                        variant="outline"
                        onClick={handleJoinPrivateRoom}
                        disabled={isLoading || !privateRoomCode}
                      >
                        Join
                      </Button>
                    </div>
                  </>
                )}
              </div>
            </div>
          )}
        </div>
      </main>
      
    </div>
  );
}