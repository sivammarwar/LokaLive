import { create } from 'zustand';
import { persist } from 'zustand/middleware';

// ✅ Sync with database gender_preference enum
type Gender = 'male' | 'female' | 'other';
type Interest = 'student' | 'music' | 'entertainment' | 'friend' | 'random' | 'iitians' | 'nitians';

interface UserState {
  id: string | null;
  displayName: string | null;
  sessionToken: string | null;
  healthTokens: number;
  
  // ✅ NEW: Fields that match database schema
  gender: Gender | null;
  interestedIn: Gender | null;
  interest: Interest | null;
  
  // Actions
  setUser: (
    id: string, 
    displayName: string, 
    sessionToken: string, 
    healthTokens: number,
    gender?: Gender | null,
    interestedIn?: Gender | null,
    interest?: Interest | null
  ) => void;
  
  clearUser: () => void;
  updateHealthTokens: (tokens: number) => void;
  
  // ✅ NEW: Update user preferences
  updateUserPreferences: (
    gender: Gender,
    interestedIn: Gender,
    interest: Interest
  ) => void;
}

export const useUserStore = create<UserState>()(
  persist(
    (set) => ({
      id: null,
      displayName: null,
      sessionToken: null,
      healthTokens: 5,
      gender: null,
      interestedIn: null,
      interest: null,
      
      setUser: (id, displayName, sessionToken, healthTokens, gender, interestedIn, interest) =>
        set({ 
          id, 
          displayName, 
          sessionToken, 
          healthTokens,
          gender: gender || null,
          interestedIn: interestedIn || null,
          interest: interest || null
        }),
      
      clearUser: () =>
        set({ 
          id: null, 
          displayName: null, 
          sessionToken: null, 
          healthTokens: 5,
          gender: null,
          interestedIn: null,
          interest: null
        }),
      
      updateHealthTokens: (tokens) => set({ healthTokens: tokens }),
      
      // ✅ NEW: Update preferences function
      updateUserPreferences: (gender, interestedIn, interest) =>
        set({ gender, interestedIn, interest }),
    }),
    {
      name: 'loka-user',
    }
  )
);