import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { RefreshCw, AlertCircle } from 'lucide-react';

interface EmergencyResetProps {
  userId: string;
  onComplete?: () => void;
}

export default function EmergencyReset({ userId, onComplete }: EmergencyResetProps) {
  const [isResetting, setIsResetting] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);

  const handleEmergencyReset = async () => {
    if (!userId) {
      toast.error('User ID not found');
      return;
    }

    setIsResetting(true);
    console.log('🚨 EMERGENCY RESET for user:', userId);

    try {
      // Step 1: Force leave all rooms
      console.log('1️⃣ Force leaving all rooms...');
      const { error: leaveError } = await supabase
        .rpc('force_leave_room', { p_user_id: userId });
      
      if (leaveError) {
        console.error('Error in force_leave_room:', leaveError);
        throw leaveError;
      }
      
      console.log('✅ Left all rooms');

      // Step 2: Update user gender if it's 'other'
      console.log('2️⃣ Checking user gender...');
      const { data: userData, error: fetchError } = await supabase
        .from('users')
        .select('gender')
        .eq('id', userId)
        .single();

      if (fetchError) {
        console.error('Error fetching user:', fetchError);
        throw fetchError;
      }

      if (userData.gender === 'other') {
        console.log('⚠️ User has gender "other", updating to "male"...');
        const { error: updateError } = await supabase
          .from('users')
          .update({ 
            gender: 'male',
            updated_at: new Date().toISOString()
          })
          .eq('id', userId);

        if (updateError) {
          console.error('Error updating gender:', updateError);
          // Don't throw, this is not critical
        } else {
          console.log('✅ Updated gender to "male"');
        }
      }

      // Step 3: Clean up inactive rooms
      console.log('3️⃣ Cleaning up inactive rooms...');
      const { data: cleanupCount, error: cleanupError } = await supabase
        .rpc('cleanup_inactive_rooms');
      
      if (!cleanupError && cleanupCount) {
        console.log(`✅ Cleaned up ${cleanupCount} inactive rooms`);
      }

      // Step 4: Wait for database sync
      console.log('4️⃣ Waiting for database sync...');
      await new Promise(resolve => setTimeout(resolve, 1000));

      // Step 5: Verify clean state
      console.log('5️⃣ Verifying clean state...');
      const { data: participations } = await supabase
        .from('room_participants')
        .select('room_id')
        .eq('user_id', userId)
        .is('left_at', null);

      if (participations && participations.length > 0) {
        console.error('❌ Still in rooms after reset:', participations);
        toast.warning('Reset complete but may need to refresh page');
      } else {
        console.log('✅ Clean state verified');
        toast.success('Reset complete! You can now create or join a room.');
      }

      setShowConfirm(false);
      
      if (onComplete) {
        onComplete();
      }

    } catch (error: any) {
      console.error('❌ Emergency reset error:', error);
      toast.error(error.message || 'Reset failed. Please refresh the page.');
    } finally {
      setIsResetting(false);
    }
  };

  if (!showConfirm) {
    return (
      <Button
        variant="destructive"
        size="sm"
        onClick={() => setShowConfirm(true)}
        className="gap-2"
      >
        <AlertCircle className="h-4 w-4" />
        Stuck? Reset
      </Button>
    );
  }

  return (
    <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-card border border-border rounded-xl p-6 max-w-md w-full space-y-4">
        <div className="flex items-center gap-3 text-destructive">
          <AlertCircle className="h-6 w-6" />
          <h3 className="text-lg font-bold">Emergency Reset</h3>
        </div>
        
        <p className="text-sm text-muted-foreground">
          This will:
        </p>
        
        <ul className="text-sm text-muted-foreground space-y-1 list-disc list-inside">
          <li>Remove you from all rooms</li>
          <li>Clean up stuck connections</li>
          <li>Fix gender if set to "other"</li>
          <li>Reset your matchmaking state</li>
        </ul>

        <p className="text-sm font-semibold text-yellow-500">
          ⚠️ Use this only if you're stuck and can't match with anyone!
        </p>

        <div className="flex gap-3">
          <Button
            variant="outline"
            onClick={() => setShowConfirm(false)}
            disabled={isResetting}
            className="flex-1"
          >
            Cancel
          </Button>
          <Button
            variant="destructive"
            onClick={handleEmergencyReset}
            disabled={isResetting}
            className="flex-1 gap-2"
          >
            {isResetting ? (
              <>
                <RefreshCw className="h-4 w-4 animate-spin" />
                Resetting...
              </>
            ) : (
              <>
                <AlertCircle className="h-4 w-4" />
                Reset Now
              </>
            )}
          </Button>
        </div>
      </div>
    </div>
  );
}

/*
USAGE IN CreateRoom.tsx:

1. Import the component:
   import EmergencyReset from '@/components/EmergencyReset';

2. Add state for showing reset:
   const [showReset, setShowReset] = useState(false);

3. Add button in header next to logout:
   <EmergencyReset 
     userId={userId} 
     onComplete={() => {
       // Optionally refresh or navigate
       window.location.reload();
     }}
   />

This gives users a way to fix their stuck state without manual database intervention!
*/