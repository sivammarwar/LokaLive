import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface UserState {
  id: string | null;
  displayName: string | null;
  sessionToken: string | null;
  healthTokens: number;
  setUser: (id: string, displayName: string, sessionToken: string, healthTokens: number) => void;
  clearUser: () => void;
  updateHealthTokens: (tokens: number) => void;
}

export const useUserStore = create<UserState>()(
  persist(
    (set) => ({
      id: null,
      displayName: null,
      sessionToken: null,
      healthTokens: 5,
      setUser: (id, displayName, sessionToken, healthTokens) =>
        set({ id, displayName, sessionToken, healthTokens }),
      clearUser: () =>
        set({ id: null, displayName: null, sessionToken: null, healthTokens: 5 }),
      updateHealthTokens: (tokens) => set({ healthTokens: tokens }),
    }),
    {
      name: 'loka-user',
    }
  )
);
