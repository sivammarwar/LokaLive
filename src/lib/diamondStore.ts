// src/lib/diamondStore.ts
import { create } from 'zustand';
import { supabase } from '@/integrations/supabase/client';

interface DiamondStore {
  diamonds: number;
  isLoading: boolean;
  setDiamonds: (diamonds: number) => void;
  addDiamonds: (amount: number) => void;
  deductDiamonds: (amount: number) => boolean;
  refreshDiamonds: (userId: string) => Promise<void>;
}

export const useDiamondStore = create<DiamondStore>((set, get) => ({
  diamonds: 0,
  isLoading: false,
  
  setDiamonds: (diamonds: number) => set({ diamonds }),
  
  addDiamonds: (amount: number) => 
    set((state) => ({ diamonds: state.diamonds + amount })),
  
  deductDiamonds: (amount: number) => {
    const current = get().diamonds;
    if (current >= amount) {
      set({ diamonds: current - amount });
      return true;
    }
    return false;
  },
  
  refreshDiamonds: async (userId: string) => {
    if (!userId) return;
    
    try {
      set({ isLoading: true });
      
      const { data, error } = await supabase
        .from('users')
        .select('diamonds')
        .eq('id', userId)
        .single();
      
      console.log('Diamond refresh - Data:', data, 'Error:', error); // Debug log
      
      if (error) throw error;
      
      if (data) {
        const newDiamonds = data.diamonds || 0;
        console.log('Setting diamonds to:', newDiamonds); // Debug log
        set({ diamonds: newDiamonds, isLoading: false });
      }
    } catch (error) {
      console.error('Error refreshing diamonds:', error);
      set({ isLoading: false });
    }
  },
}));

// Rest of your code stays the same...
export interface DiamondPackage {
  id: string;
  diamonds: number;
  price: number;
  bonus?: number;
  popular?: boolean;
}

export const DIAMOND_PACKAGES: DiamondPackage[] = [
  {
    id: 'pack_15',
    diamonds: 15,
    price: 100,
  },
  {
    id: 'pack_80',
    diamonds: 80,
    price: 500,
    bonus: 5,
    popular: true,
  },
  {
    id: 'pack_170',
    diamonds: 170,
    price: 1000,
    bonus: 20,
  },
];

export const DIAMOND_VALUE_IN_RUPEES = 5;
export const MIN_WITHDRAWAL_DIAMONDS = 15;
export const MAX_BET_DIAMONDS = 1000;